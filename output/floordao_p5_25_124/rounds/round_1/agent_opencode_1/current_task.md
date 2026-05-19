You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/floordao/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol (309 LOC) — TODO
- 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/interfaces/IDistributor.sol (27 LOC) — TODO
- 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/interfaces/IERC20.sol (73 LOC) — TODO
- 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/interfaces/IFloorAuthority.sol (23 LOC) — TODO
- 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/interfaces/IgFLOOR.sol (16 LOC) — TODO
- 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/interfaces/IsFLOOR.sol (29 LOC) — TODO
- 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/libraries/SafeERC20.sol (52 LOC) — TODO
- 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/libraries/SafeMath.sol (63 LOC) — TODO
- 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/types/FloorAccessControlled.sol (55 LOC) — TODO

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
