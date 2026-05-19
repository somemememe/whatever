You are auditing the smart contracts in /Users/lu/Desktop/Red_V1G/2025-06-notional-exponent/notional-v4/src.

## Contracts in Scope

# Scope

- AbstractYieldStrategy.sol (479 LOC) — TODO
- oracles/AbstractCustomOracle.sol (90 LOC) — TODO
- oracles/AbstractLPOracle.sol (111 LOC) — TODO
- oracles/Curve2TokenOracle.sol (108 LOC) — TODO
- oracles/PendlePTOracle.sol (90 LOC) — TODO
- proxy/AddressRegistry.sol (151 LOC) — TODO
- proxy/Initializable.sol (20 LOC) — TODO
- proxy/TimelockUpgradeableProxy.sol (87 LOC) — TODO
- rewards/AbstractRewardManager.sol (320 LOC) — TODO
- rewards/ConvexRewardManager.sol (31 LOC) — TODO
- rewards/RewardManagerMixin.sol (194 LOC) — TODO
- routers/AbstractLendingRouter.sol (329 LOC) — TODO
- routers/MorphoLendingRouter.sol (287 LOC) — TODO
- single-sided-lp/AbstractSingleSidedLP.sol (418 LOC) — TODO
- single-sided-lp/CurveConvex2Token.sol (310 LOC) — TODO
- staking/AbstractStakingStrategy.sol (151 LOC) — TODO
- staking/PendlePT.sol (146 LOC) — TODO
- staking/PendlePTLib.sol (89 LOC) — TODO
- staking/PendlePT_sUSDe.sol (71 LOC) — TODO
- staking/StakingStrategy.sol (15 LOC) — TODO
- utils/Constants.sol (20 LOC) — TODO
- utils/TokenUtils.sol (54 LOC) — TODO
- utils/TypeConvert.sol (26 LOC) — TODO
- withdraws/AbstractWithdrawRequestManager.sol (342 LOC) — TODO
- withdraws/ClonedCooldownHolder.sol (38 LOC) — TODO
- withdraws/Dinero.sol (89 LOC) — TODO
- withdraws/Ethena.sol (102 LOC) — TODO
- withdraws/EtherFi.sol (57 LOC) — TODO
- withdraws/GenericERC20.sol (42 LOC) — TODO
- withdraws/GenericERC4626.sol (45 LOC) — TODO
- withdraws/Origin.sol (52 LOC) — TODO

# Notes

- Auto-generated file-level map.
- Descriptions are placeholders and can be edited later.
- Excluded from direct audit scope: interfaces/** 


## Excluded From Direct Audit Scope

Do not report findings whose root cause exists solely in files matching:
- `interfaces/** `

You may still read those files when they define interfaces, structs, errors, or external integration context used by in-scope implementation files.


## Known Findings (do NOT repeat — find NEW issues)

- F-001: Dinero withdrawal finalization condition is inverted (High, high)
- F-002: Morpho market oracle uses account-agnostic vault price and can misprice pending-withdraw collateral (High, medium)
- F-003: LP zero-balance legs create missing withdraw requests that break pending valuation and finalization (Medium, high)
- F-004: Reward debt is advanced even when reward transfer fails (Medium, high)
- F-005: Zero-yield-token withdraw requests can trigger division-by-zero on finalization accounting (Low, medium)
- F-007: Ethena zero-duration cooldown mode strands redeemed USDe in cloned holder (Medium, high)
- F-008: Dinero withdrawals never request validator exits (Low, medium)
- F-009: Dinero request-id nonce overflows after 65,535 withdrawals and halts new requests (Low, high)
- F-010: Router transfer authorization is not bound to the intended source account (Low, medium)
- F-011: Any whitelisted lending router can delete another router's live position record (Low, high)
- F-012: Sequencer outage protection is skipped on legacy oracle accessors (Low, low)

## Optional Prior Round Summary

An optional prior round summary is available at:
- `/Users/lu/Desktop/Red_V1G/AuditHoundV2/output/src_1776262343/rounds/round_3/round_summary.md`

Read it only if useful, and think it before you use it.It may not be very concise.


## Task

Find security vulnerabilities in the contracts listed above as more as you can.

You should look for:
- vulnerabilities
- reportable issues

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
