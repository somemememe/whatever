You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/orion/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x7fbd6b0e72588751f7ffc25e8df2612c2655be77/Contract.sol (0 LOC) — TODO
- 0xb5599f568d3f3e6113b286d010d2bca40a7745aa/@openzeppelin/contracts/utils/Address.sol (165 LOC) — TODO
- 0xb5599f568d3f3e6113b286d010d2bca40a7745aa/contracts/proxy/AdminUpgradeabilityProxy.sol (136 LOC) — TODO
- 0xb5599f568d3f3e6113b286d010d2bca40a7745aa/contracts/proxy/Proxy.sol (77 LOC) — TODO
- 0xb5599f568d3f3e6113b286d010d2bca40a7745aa/contracts/proxy/UpgradeabilityProxy.sol (78 LOC) — TODO

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
