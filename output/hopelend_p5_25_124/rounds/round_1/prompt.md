You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/hopelend/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol (124 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/dependencies/openzeppelin/contracts/Address.sol (61 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol (80 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/dependencies/openzeppelin/contracts/SafeCast.sol (255 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/flashloan/interfaces/IFlashLoanReceiver.sol (36 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol (36 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IACLManager.sol (175 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IAbsGauge.sol (13 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IERC20WithPermit.sol (33 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IGaugeController.sol (138 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IHToken.sol (163 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IHTokenRewards.sol (30 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IInitializableDebtToken.sol (47 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IInitializableHToken.sol (51 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/ILT.sol (69 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/ILendingGauge.sol (40 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IMinter.sol (12 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IPool.sol (786 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IPoolAddressesProvider.sol (227 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IPriceOracleGetter.sol (30 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IPriceOracleSentinel.sol (67 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IReserveInterestRateStrategy.sol (27 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IScaledBalanceToken.sol (72 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IStableDebtToken.sol (153 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IVariableDebtToken.sol (50 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IVariableDebtTokenRewards.sol (28 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/interfaces/IVotingEscrow.sol (98 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol (660 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/configuration/UserConfiguration.sol (251 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/helpers/Errors.sol (109 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/helpers/Helpers.sol (29 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/hopelend-upgradeability/VersionedInitializable.sol (77 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/BorrowLogic.sol (380 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/BridgeLogic.sol (158 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/EModeLogic.sol (121 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/FlashLoanLogic.sol (273 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/GenericLogic.sol (280 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/IsolationModeLogic.sol (63 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/LiquidationLogic.sol (562 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/PoolLogic.sol (213 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/ReserveLogic.sol (370 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/SupplyLogic.sol (309 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/ValidationLogic.sol (716 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/math/MathUtils.sol (101 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/math/PercentageMath.sol (61 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/math/WadRayMath.sol (126 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/types/DataTypes.sol (279 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/pool/Pool.sol (690 LOC) — TODO
- 0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/pool/PoolStorage.sol (58 LOC) — TODO
- 0x53fbcada1201a465740f2d64ecdf6fac425f9030/lend-core/contracts/dependencies/openzeppelin/contracts/Address.sol (61 LOC) — TODO
- 0x53fbcada1201a465740f2d64ecdf6fac425f9030/lend-core/contracts/dependencies/openzeppelin/upgradeability/BaseUpgradeabilityProxy.sol (66 LOC) — TODO
- 0x53fbcada1201a465740f2d64ecdf6fac425f9030/lend-core/contracts/dependencies/openzeppelin/upgradeability/InitializableUpgradeabilityProxy.sol (29 LOC) — TODO
- 0x53fbcada1201a465740f2d64ecdf6fac425f9030/lend-core/contracts/dependencies/openzeppelin/upgradeability/Proxy.sol (73 LOC) — TODO
- 0x53fbcada1201a465740f2d64ecdf6fac425f9030/lend-core/contracts/protocol/libraries/hopelend-upgradeability/BaseImmutableAdminUpgradeabilityProxy.sol (86 LOC) — TODO
- 0x53fbcada1201a465740f2d64ecdf6fac425f9030/lend-core/contracts/protocol/libraries/hopelend-upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol (29 LOC) — TODO

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
