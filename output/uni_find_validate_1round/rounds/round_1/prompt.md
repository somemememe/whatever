You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/uni/src.

## Contracts in Scope

# Scope

- 0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol (496 LOC) — TODO

# Notes

- Auto-generated file-level map.
- Descriptions are placeholders and can be edited later.




## Known Findings (do not duplicate)

- F-002: Positive-balance token mechanics let anyone skim unaccounted surplus from the pair (Medium, medium)
- F-003: Balance-decreasing tokens can desynchronize reserves, DoS swaps, and force LP losses on sync (Medium, medium)


## Optional Global Audit Memory

An optional global audit memory is available at:
- `/Users/zhanglongqin/AuditHoundV2/output/uni_find_validate_1round/global_summary.md`

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
