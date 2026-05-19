You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/inversefinance/src.

## Contracts in Scope

# Scope

- 0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CErc20.sol (198 LOC) — TODO
- 0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CErc20Immutable.sol (39 LOC) — TODO
- 0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol (1428 LOC) — TODO
- 0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CTokenInterfaces.sol (302 LOC) — TODO
- 0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CarefulMath.sol (85 LOC) — TODO
- 0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/ComptrollerInterface.sol (71 LOC) — TODO
- 0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/EIP20Interface.sol (62 LOC) — TODO
- 0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/EIP20NonStandardInterface.sol (70 LOC) — TODO
- 0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/ErrorReporter.sol (207 LOC) — TODO
- 0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/Exponential.sol (183 LOC) — TODO
- 0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/ExponentialNoError.sol (195 LOC) — TODO
- 0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/InterestRateModel.sol (30 LOC) — TODO

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
