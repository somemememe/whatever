You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/mimspell2/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x7259e152103756e1616a77ae982353c3751a6a90/lib/BoringSolidity/contracts/BoringOwnable.sol (63 LOC) — TODO
- 0x7259e152103756e1616a77ae982353c3751a6a90/lib/BoringSolidity/contracts/Domain.sol (38 LOC) — TODO
- 0x7259e152103756e1616a77ae982353c3751a6a90/lib/BoringSolidity/contracts/ERC20.sol (140 LOC) — TODO
- 0x7259e152103756e1616a77ae982353c3751a6a90/lib/BoringSolidity/contracts/interfaces/IERC20.sol (57 LOC) — TODO
- 0x7259e152103756e1616a77ae982353c3751a6a90/lib/BoringSolidity/contracts/interfaces/IMasterContract.sol (10 LOC) — TODO
- 0x7259e152103756e1616a77ae982353c3751a6a90/lib/BoringSolidity/contracts/libraries/BoringERC20.sol (106 LOC) — TODO
- 0x7259e152103756e1616a77ae982353c3751a6a90/lib/BoringSolidity/contracts/libraries/BoringRebase.sol (104 LOC) — TODO
- 0x7259e152103756e1616a77ae982353c3751a6a90/src/cauldrons/CauldronV4.sol (715 LOC) — TODO
- 0x7259e152103756e1616a77ae982353c3751a6a90/src/interfaces/IBentoBoxOwner.sol (8 LOC) — TODO
- 0x7259e152103756e1616a77ae982353c3751a6a90/src/interfaces/IBentoBoxV1.sol (177 LOC) — TODO
- 0x7259e152103756e1616a77ae982353c3751a6a90/src/interfaces/IOracle.sol (41 LOC) — TODO
- 0x7259e152103756e1616a77ae982353c3751a6a90/src/interfaces/IStrategy.sol (26 LOC) — TODO
- 0x7259e152103756e1616a77ae982353c3751a6a90/src/interfaces/ISwapperV2.sol (18 LOC) — TODO
- 0x7259e152103756e1616a77ae982353c3751a6a90/src/libraries/compat/BoringMath.sol (38 LOC) — TODO

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
