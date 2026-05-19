You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/mahalend/src/onchain_auto.

## Contracts in Scope

# Scope

- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/dependencies/gnosis/contracts/GPv2SafeERC20.sol (124 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/dependencies/openzeppelin/contracts/Address.sol (61 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol (80 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/dependencies/openzeppelin/contracts/SafeCast.sol (255 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/flashloan/interfaces/IFlashLoanReceiver.sol (36 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol (36 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/interfaces/IACLManager.sol (175 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/interfaces/IAToken.sol (150 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/interfaces/IAaveIncentivesController.sol (176 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/interfaces/IERC20WithPermit.sol (33 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/interfaces/IInitializableAToken.sol (56 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/interfaces/IInitializableDebtToken.sol (52 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/interfaces/IPool.sol (747 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/interfaces/IPoolAddressesProvider.sol (227 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/interfaces/IPriceOracleGetter.sol (30 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/interfaces/IPriceOracleSentinel.sol (67 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/interfaces/IReserveInterestRateStrategy.sol (39 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/interfaces/IScaledBalanceToken.sol (71 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/interfaces/IStableDebtToken.sol (153 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/interfaces/IVariableDebtToken.sol (50 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/aave-upgradeability/VersionedInitializable.sol (77 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol (633 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/configuration/UserConfiguration.sol (251 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/helpers/Errors.sol (100 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/helpers/Helpers.sol (29 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/BorrowLogic.sol (349 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/BridgeLogic.sol (141 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/EModeLogic.sol (121 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/FlashLoanLogic.sol (262 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/GenericLogic.sol (280 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/IsolationModeLogic.sol (64 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/LiquidationLogic.sol (538 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/PoolLogic.sol (192 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/ReserveLogic.sol (362 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/SupplyLogic.sol (290 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/logic/ValidationLogic.sol (726 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/math/MathUtils.sol (101 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/math/PercentageMath.sol (61 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/math/WadRayMath.sol (126 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/libraries/types/DataTypes.sol (268 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/pool/Pool.sol (773 LOC) — TODO
- 0xfd11aba71c06061f446ade4eec057179f19c23c4/@mahalend/core-v3/contracts/protocol/pool/PoolStorage.sol (51 LOC) — TODO

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
