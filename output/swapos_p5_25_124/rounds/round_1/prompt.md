You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/swapos/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x8ce2f9286f50fbe2464bfd881fab8effc8dc584f/contracts/SwaposV2ERC20.sol (94 LOC) — TODO
- 0x8ce2f9286f50fbe2464bfd881fab8effc8dc584f/contracts/SwaposV2Pair.sol (201 LOC) — TODO
- 0x8ce2f9286f50fbe2464bfd881fab8effc8dc584f/contracts/interfaces/IERC20.sol (17 LOC) — TODO
- 0x8ce2f9286f50fbe2464bfd881fab8effc8dc584f/contracts/interfaces/ISwaposV2Callee.sol (5 LOC) — TODO
- 0x8ce2f9286f50fbe2464bfd881fab8effc8dc584f/contracts/interfaces/ISwaposV2ERC20.sol (23 LOC) — TODO
- 0x8ce2f9286f50fbe2464bfd881fab8effc8dc584f/contracts/interfaces/ISwaposV2Factory.sol (18 LOC) — TODO
- 0x8ce2f9286f50fbe2464bfd881fab8effc8dc584f/contracts/interfaces/ISwaposV2Pair.sol (52 LOC) — TODO
- 0x8ce2f9286f50fbe2464bfd881fab8effc8dc584f/contracts/libraries/Math.sol (23 LOC) — TODO
- 0x8ce2f9286f50fbe2464bfd881fab8effc8dc584f/contracts/libraries/SafeMath.sol (17 LOC) — TODO
- 0x8ce2f9286f50fbe2464bfd881fab8effc8dc584f/contracts/libraries/UQ112x112.sol (20 LOC) — TODO

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
