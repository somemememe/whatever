You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/roefinance/src.

## Contracts in Scope

# Scope

- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/adapters/BaseParaSwapAdapter.sol (122 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/adapters/BaseParaSwapSellAdapter.sol (109 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/adapters/BaseUniswapAdapter.sol (566 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/adapters/FlashLiquidationAdapter.sol (184 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/adapters/ParaSwapLiquiditySwapAdapter.sol (210 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/adapters/UniswapLiquiditySwapAdapter.sol (283 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/adapters/UniswapRepayAdapter.sol (266 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/adapters/interfaces/IBaseUniswapAdapter.sol (90 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/contracts/Address.sol (61 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/contracts/Context.sol (23 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/contracts/ERC20.sol (344 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/contracts/IERC20.sol (80 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol (12 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/contracts/Ownable.sol (69 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/contracts/ReentrancyGuard.sol (62 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/contracts/SafeERC20.sol (64 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/contracts/SafeMath.sol (163 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/upgradeability/AdminUpgradeabilityProxy.sol (36 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/upgradeability/BaseAdminUpgradeabilityProxy.sol (126 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/upgradeability/BaseUpgradeabilityProxy.sol (66 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/upgradeability/InitializableAdminUpgradeabilityProxy.sol (42 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/upgradeability/InitializableUpgradeabilityProxy.sol (29 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/upgradeability/Proxy.sol (72 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/dependencies/openzeppelin/upgradeability/UpgradeabilityProxy.sol (28 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/deployments/ATokensAndRatesHelper.sol (86 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/deployments/StableAndVariableTokensHelper.sol (47 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/deployments/StringLib.sol (8 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/flashloan/base/FlashLoanReceiverBase.sol (22 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/flashloan/interfaces/IFlashLoanReceiver.sol (25 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IAToken.sol (107 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IAaveIncentivesController.sol (148 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IChainlinkAggregator.sol (17 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/ICreditDelegationToken.sol (28 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IDelegationToken.sol (11 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IERC20WithPermit.sol (16 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IExchangeAdapter.sol (23 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IInitializableAToken.sol (55 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IInitializableDebtToken.sol (51 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/ILendingPool.sol (410 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/ILendingPoolAddressesProvider.sol (60 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/ILendingPoolAddressesProviderRegistry.sol (26 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/ILendingPoolCollateralManager.sol (60 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/ILendingPoolConfigurator.sol (179 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/ILendingRateOracle.sol (19 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IParaSwapAugustus.sol (7 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IParaSwapAugustusRegistry.sol (7 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IPriceOracleGetter.sol (16 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IReserveInterestRateStrategy.sol (47 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IScaledBalanceToken.sol (26 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IStableDebtToken.sol (133 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IUniswapV2Router02.sol (30 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/interfaces/IVariableDebtToken.sol (62 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/misc/AaveOracle.sol (127 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/misc/AaveProtocolDataProvider.sol (180 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/misc/UiPoolDataProvider.sol (405 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/misc/WETHGateway.sol (189 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/misc/WalletBalanceProvider.sol (111 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/misc/interfaces/IUiPoolDataProvider.sol (110 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/misc/interfaces/IWETH.sol (16 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/misc/interfaces/IWETHGateway.sol (30 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/mocks/flashloan/MockFlashLoanReceiver.sol (84 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/mocks/oracle/LendingRateOracle.sol (26 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/mocks/swap/MockParaSwapAugustus.sol (59 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/mocks/swap/MockParaSwapAugustusRegistry.sol (17 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/mocks/swap/MockParaSwapTokenTransferProxy.sol (17 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/mocks/swap/MockUniswapV2Router02.sol (106 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/mocks/tokens/MintableDelegationERC20.sol (34 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/mocks/tokens/MintableERC20.sol (28 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/mocks/upgradeability/MockAToken.sol (12 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/mocks/upgradeability/MockStableDebtToken.sol (10 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/mocks/upgradeability/MockVariableDebtToken.sol (10 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/configuration/LendingPoolAddressesProvider.sol (215 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/configuration/LendingPoolAddressesProviderRegistry.sol (89 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/lendingpool/DefaultReserveInterestRateStrategy.sol (260 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/lendingpool/LendingPool.sol (1048 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/lendingpool/LendingPoolCollateralManager.sol (317 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/lendingpool/LendingPoolConfigurator.sol (487 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/lendingpool/LendingPoolStorage.sol (32 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/aave-upgradeability/BaseImmutableAdminUpgradeabilityProxy.sol (80 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/aave-upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol (23 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/aave-upgradeability/VersionedInitializable.sol (77 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/configuration/ReserveConfiguration.sol (366 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/configuration/UserConfiguration.sol (111 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/helpers/Errors.sol (119 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/helpers/Helpers.sol (39 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/logic/GenericLogic.sol (275 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/logic/ReserveLogic.sol (373 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/logic/ValidationLogic.sol (469 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/math/MathUtils.sol (84 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/math/PercentageMath.sol (54 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/math/WadRayMath.sol (135 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/libraries/types/DataTypes.sol (49 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/tokenization/AToken.sol (406 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/tokenization/DelegationAwareAToken.sol (30 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/tokenization/IncentivizedERC20.sol (255 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/tokenization/StableDebtToken.sol (435 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/tokenization/VariableDebtToken.sol (209 LOC) — TODO
- 0x574ff39184dee9e46f6c3229b95e0e0938e398d0/contracts/protocol/tokenization/base/DebtTokenBase.sol (137 LOC) — TODO
- 0x5f360c6b7b25dfbfa4f10039ea0f7ecfb9b02e60/Contract.sol (1 LOC) — TODO

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
