You are auditing the smart contracts in /Users/lu/Desktop/Red_V1G/2024-12-lambowin/src.

## Contracts in Scope

# Scope

- LamboFactory.sol (84 LOC) — TODO
- LamboToken.sol (290 LOC) — TODO
- LamboVEthRouter.sol (189 LOC) — TODO
- Utils/LaunchPadUtils.sol (25 LOC) — TODO
- VirtualToken.sol (151 LOC) — TODO
- rebalance/LamboRebalanceOnUniwap.sol (169 LOC) — TODO

# Notes

- Auto-generated file-level map.
- Descriptions are placeholders and can be edited later.
- Excluded from direct audit scope: interfaces/**, libraries/**



## Excluded From Direct Audit Scope

Do not report findings whose root cause exists solely in files matching:
- `interfaces/**`
- `libraries/**`

You may still read those files when they define interfaces, structs, errors, or external integration context used by in-scope implementation files.


## Known Findings (do NOT repeat — find NEW issues)

None yet.



## Task

Find security vulnerabilities in the contracts listed above as more as you can.And there are lots of high severity vulns.

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
