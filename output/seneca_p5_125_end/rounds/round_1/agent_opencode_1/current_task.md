You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/seneca/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/@openzeppelin/contracts/access/Ownable.sol (83 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/@openzeppelin/contracts/access/Ownable2Step.sol (57 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/@openzeppelin/contracts/security/Pausable.sol (105 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/@openzeppelin/contracts/token/ERC20/IERC20.sol (78 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol (60 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol (143 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/@openzeppelin/contracts/utils/Address.sol (244 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/@openzeppelin/contracts/utils/Context.sol (24 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/@openzeppelin/contracts/utils/math/SafeCast.sol (1136 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/@openzeppelin/contracts/utils/math/SafeMath.sol (215 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/contracts/Chamber2.sol (643 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/contracts/Constants.sol (45 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/contracts/interfaces/IBentoBoxV1.sol (177 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/contracts/interfaces/IMasterContract.sol (10 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/contracts/interfaces/IOracle.sol (45 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/contracts/interfaces/IStrategy.sol (26 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/contracts/interfaces/ISwapperV2.sol (18 LOC) — TODO
- 0x65c210c59b43eb68112b7a4f75c8393c36491f06/contracts/libraries/BoringRebase.sol (104 LOC) — TODO

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
