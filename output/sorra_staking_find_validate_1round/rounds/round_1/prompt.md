You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/sorra_staking/src.

## Contracts in Scope

# Scope

- 0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/@openzeppelin/contracts/access/Ownable.sol (100 LOC) — TODO
- 0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/@openzeppelin/contracts/interfaces/IERC1363.sol (86 LOC) — TODO
- 0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/@openzeppelin/contracts/interfaces/IERC165.sol (6 LOC) — TODO
- 0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/@openzeppelin/contracts/interfaces/IERC20.sol (6 LOC) — TODO
- 0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/@openzeppelin/contracts/token/ERC20/IERC20.sol (79 LOC) — TODO
- 0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol (199 LOC) — TODO
- 0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/@openzeppelin/contracts/utils/Address.sol (150 LOC) — TODO
- 0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/@openzeppelin/contracts/utils/Context.sol (28 LOC) — TODO
- 0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/@openzeppelin/contracts/utils/Errors.sol (34 LOC) — TODO
- 0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/@openzeppelin/contracts/utils/ReentrancyGuard.sol (87 LOC) — TODO
- 0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/@openzeppelin/contracts/utils/introspection/IERC165.sol (25 LOC) — TODO
- 0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/interfaces/IPoolExtension.sol (10 LOC) — TODO
- 0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol (279 LOC) — TODO

# Notes

- Auto-generated file-level map.
- Descriptions are placeholders and can be edited later.




## Known Findings (do not duplicate)

- F-001: Matured rewards can be claimed repeatedly by splitting withdrawals (Critical, high)
- F-002: Rewards are paid from the same token pool that backs user principal, so early withdrawals can consume later deposits (High, high)
- F-003: Fee-on-transfer or deflationary tokens make internal balances exceed real assets (Medium, medium)
- F-004: Owner emergency withdrawal can seize all staked funds (High, medium)


## Optional Global Audit Memory

An optional global audit memory is available at:
- `/Users/zhanglongqin/AuditHoundV2/output/sorra_staking_find_validate_1round/global_summary.md`

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
