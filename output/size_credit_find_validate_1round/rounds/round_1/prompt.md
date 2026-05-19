You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/size_credit/src/onchain_auto.

## Contracts in Scope

# Scope

- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol (76 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/aave-v3-core/contracts/interfaces/IAToken.sol (138 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/aave-v3-core/contracts/interfaces/IAaveIncentivesController.sol (19 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/aave-v3-core/contracts/interfaces/IInitializableAToken.sol (56 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/aave-v3-core/contracts/interfaces/IPool.sol (737 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol (227 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/aave-v3-core/contracts/interfaces/IScaledBalanceToken.sol (72 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/aave-v3-core/contracts/protocol/libraries/math/WadRayMath.sol (126 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/aave-v3-core/contracts/protocol/libraries/types/DataTypes.sol (265 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol (19 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/access/Ownable.sol (100 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/interfaces/IERC20Metadata.sol (6 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC1822.sol (20 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol (161 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol (193 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol (16 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol (316 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol (79 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol (26 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol (90 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol (118 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/utils/Address.sol (159 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/utils/Context.sol (28 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol (135 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/utils/Strings.sol (94 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/utils/math/Math.sol (415 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol (1153 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol (43 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol (80 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol (119 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol (228 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol (153 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol (34 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/core/Market/MarketMathCore.sol (417 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/core/StandardizedYield/PYIndex.sol (50 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/core/StandardizedYield/SYUtils.sol (22 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/core/libraries/Errors.sol (182 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/core/libraries/MiniHelpers.sol (16 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/core/libraries/math/LogExpMath.sol (495 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/core/libraries/math/PMath.sol (225 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPActionAddRemoveLiqV3.sol (109 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPActionCallbackV3.sol (7 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPActionMiscV3.sol (141 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPActionSimple.sol (65 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPActionStorageV4.sol (23 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPActionSwapPTV3.sol (43 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPActionSwapYTV3.sol (43 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPAllActionTypeV3.sol (141 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPAllActionV3.sol (21 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPAllEventsV3.sol (266 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPGauge.sol (11 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPInterestManagerYT.sol (8 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPLimitRouter.sol (153 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPMarket.sol (93 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPMarketSwapCallback.sol (6 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPPrincipalToken.sol (21 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IPYieldToken.sol (62 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IRewardManager.sol (6 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/interfaces/IStandardizedYield.sol (167 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/oracles/PtYtLpOracle/samples/BoringPtSeller.sol (34 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/router/math/MarketApproxLibV2.sol (479 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/pendle-core-v2-public/contracts/router/swap-aggregator/IPSwapAggregator.sol (37 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/solady/src/utils/FixedPointMathLib.sol (1075 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol (26 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolActions.sol (103 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolDerivedState.sol (40 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolErrors.sol (19 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolEvents.sol (121 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol (35 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolOwnerActions.sol (23 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolState.sol (117 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/v3-core/contracts/libraries/FullMath.sol (128 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/v3-core/contracts/libraries/TickMath.sol (214 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/v3-periphery/contracts/libraries/OracleLibrary.sol (186 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/lib/v3-periphery/contracts/libraries/PoolAddress.sol (50 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/factory/interfaces/ISizeFactory.sol (61 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/factory/interfaces/ISizeFactoryOffchainGetters.sol (47 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/factory/interfaces/ISizeFactoryV1_7.sol (38 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/factory/libraries/Authorization.sol (97 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/SizeStorage.sol (132 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/SizeViewData.sol (42 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/interfaces/IMulticall.sol (14 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/interfaces/ISize.sol (206 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/interfaces/ISizeAdmin.sol (32 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/interfaces/ISizeView.sol (134 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/interfaces/IWETH.sol (10 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/interfaces/v1.7/ISizeV1_7.sol (84 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/interfaces/v1.7/ISizeViewV1_7.sol (14 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/AccountingLibrary.sol (357 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/CapsLibrary.sol (78 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/DepositTokenLibrary.sol (73 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/Errors.sol (108 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/Events.sol (154 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/LoanLibrary.sol (187 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/Math.sol (65 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/OfferLibrary.sol (208 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/RiskLibrary.sol (147 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/YieldCurveLibrary.sol (144 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/BuyCreditLimit.sol (81 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/BuyCreditMarket.sol (272 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/Claim.sol (60 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/Compensate.sol (150 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/CopyLimitOrders.sol (141 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/Deposit.sol (114 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/Initialize.sol (303 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/Liquidate.sol (141 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/LiquidateWithReplacement.sol (165 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/PartialRepay.sol (97 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/Repay.sol (63 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/SelfLiquidate.sol (96 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/SellCreditLimit.sol (80 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/SellCreditMarket.sol (269 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/SetUserConfiguration.sol (106 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/UpdateConfig.sol (149 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/libraries/actions/Withdraw.sol (91 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/token/NonTransferrableScaledTokenV1_5.sol (266 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/market/token/NonTransferrableToken.sol (57 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/oracle/IPriceFeed.sol (12 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/oracle/adapters/ChainlinkPriceFeed.sol (93 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/oracle/adapters/ChainlinkSequencerUptimeFeed.sol (43 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/oracle/adapters/UniswapV3PriceFeed.sol (85 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/lib/size-solidity/src/oracle/v1.5.1/PriceFeed.sol (86 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/src/authorization/IRequiresAuthorization.sol (8 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/src/interfaces/dex/I1InchAggregator.sol (9 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/src/interfaces/dex/IUniswapV2Router02.sol (12 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/src/interfaces/dex/IUniswapV3Router.sol (16 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/src/interfaces/dex/IUnoswapRouter.sol (9 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/src/libraries/PeripheryErrors.sol (14 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/src/liquidator/DexSwap.sol (237 LOC) — TODO
- 0xf4a21ac7e51d17a0e1c8b59f7a98bb7a97806f14/src/zaps/LeverageUp.sol (203 LOC) — TODO

# Notes

- Auto-generated file-level map.
- Descriptions are placeholders and can be edited later.




## Known Findings (do not duplicate)

None yet.



## Task

Find security vulnerabilities in the contracts listed above as more as you can.And there are lots of high severity vulns.

You should look for:
- vulnerabilities
- reportable issues

Known findings are not proof that a file, function, or theme is fully audited.
Do not repeat the same root cause, but keep investigating nearby code and related mechanisms.
Report a new finding when it has a distinct root cause, exploit path, impact, or materially stronger version of an existing issue.

Audit only Solidity source files under the target directory above.
Do not inspect or rely on files outside that directory, including README, docs, audit reports, discord exports, scripts, broadcasts, or other repository context, unless they are explicitly included in the target directory.

If you identify a problem that is not fully proven, still report it as a low-confidence finding.
Be skeptical of documented behavior and pure owner-only configuration issues, but you may still report them when they create realistic protocol-level harm such as fund loss, theft, insolvency, permanent lockup, economic manipulation, or permissionless denial of service.

## Output Format

Return ONLY a JSON array.

Each element must have:
- `id`: local finding id such as `F-001`
- `severity`: `Critical` / `High` / `Medium` / `Low` / `Informational`
- `confidence`: `high` / `medium` / `low`
- `title`: one-line summary
- `locations`: array of `file:line`
- `claim`: core mechanism statement
- `impact`: why it matters
- `paths`: array of trigger/exploit paths, may be empty

If there are no findings, return `[]`.
