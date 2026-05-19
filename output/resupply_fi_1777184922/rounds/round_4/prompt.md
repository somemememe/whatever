You are auditing the smart contracts in /Users/zhanglongqin/audithoundv2/cases/resupply_fi/src.

## Contracts in Scope

# Scope

- node_modules/@openzeppelin/contracts/interfaces/IERC1363.sol (86 LOC) — TODO
- node_modules/@openzeppelin/contracts/interfaces/IERC165.sol (6 LOC) — TODO
- node_modules/@openzeppelin/contracts/interfaces/IERC20.sol (6 LOC) — TODO
- node_modules/@openzeppelin/contracts/interfaces/draft-IERC6093.sol (161 LOC) — TODO
- node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol (311 LOC) — TODO
- node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol (79 LOC) — TODO
- node_modules/@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol (26 LOC) — TODO
- node_modules/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol (212 LOC) — TODO
- node_modules/@openzeppelin/contracts/utils/Context.sol (28 LOC) — TODO
- node_modules/@openzeppelin/contracts/utils/ReentrancyGuard.sol (87 LOC) — TODO
- node_modules/@openzeppelin/contracts/utils/introspection/IERC165.sol (25 LOC) — TODO
- node_modules/@openzeppelin/contracts/utils/math/SafeCast.sol (1162 LOC) — TODO
- src/dependencies/CoreOwnable.sol (27 LOC) — TODO
- src/dependencies/EpochTracker.sol (24 LOC) — TODO
- src/interfaces/IAuthHook.sol (7 LOC) — TODO
- src/interfaces/IConvexStaking.sol (25 LOC) — TODO
- src/interfaces/ICore.sol (31 LOC) — TODO
- src/interfaces/IERC4626.sol (48 LOC) — TODO
- src/interfaces/IFeeDeposit.sol (11 LOC) — TODO
- src/interfaces/ILiquidationHandler.sol (13 LOC) — TODO
- src/interfaces/IMintable.sol (7 LOC) — TODO
- src/interfaces/IOracle.sol (10 LOC) — TODO
- src/interfaces/IRateCalculator.sol (14 LOC) — TODO
- src/interfaces/IResupplyRegistry.sol (73 LOC) — TODO
- src/interfaces/ISwapper.sol (13 LOC) — TODO
- src/libraries/VaultAccount.sol (39 LOC) — TODO
- src/protocol/ResupplyPair.sol (450 LOC) — TODO
- src/protocol/RewardDistributorMultiEpoch.sol (321 LOC) — TODO
- src/protocol/WriteOffToken.sol (50 LOC) — TODO
- src/protocol/pair/ResupplyPairConstants.sol (32 LOC) — TODO
- src/protocol/pair/ResupplyPairCore.sol (1252 LOC) — TODO

# Notes

- Auto-generated file-level map.
- Descriptions are placeholders and can be edited later.




## Known Findings (do not duplicate)

- F-001: Oracle decimal scaling is ignored, so non-18-decimal feeds misprice collateral by orders of magnitude (High, high)
- F-002: Rewards claimed while no borrow shares exist become permanently stranded in the pair (Medium, high)
- F-003: Unchecked Convex staking results can leave credited collateral unstaked and later lock withdrawals/liquidations (Medium, medium)
- F-004: Convex pool migration mishandles the sentinel `pid == 0` and can orphan all collateral (High, high)
- F-005: Unconditional reward claiming can globally freeze borrowing, repayments, withdrawals, and liquidations (High, medium)
- F-007: Zero oracle prices cause division-by-zero reverts across critical pair flows (High, medium)
- F-009: Share-refactor floor rounding can leak small amounts of debt and leave unowned borrow shares (Low, medium)

## Optional Prior Round Summary

An optional prior round summary is available at:
- `/Users/zhanglongqin/AuditHoundV2/output/resupply_fi_1777184922/rounds/round_3/round_summary.md`

Read it only if useful, and think it before you use it.It may not be very concise.


## Optional Global Audit Memory

An optional global audit memory is available at:
- `/Users/zhanglongqin/AuditHoundV2/output/resupply_fi_1777184922/global_summary.md`

Read it only if useful. It is historical context, not a coverage guarantee,
not proof that any area is safe, and not a priority list.


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
