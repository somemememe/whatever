You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/teamfinance/src.

## Contracts in Scope

# Scope

- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol (1002 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/interfaces/IERC20Extended.sol (5 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/interfaces/IERC721Extended.sol (10 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/interfaces/IPriceEstimator.sol (21 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/interfaces/IUniswapV3PositionManager.sol (27 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/interfaces/IV3Migrator.sol (44 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/GSN/Context.sol (38 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol (62 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol (79 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/introspection/IERC165.sol (22 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol (150 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol (75 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol (75 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/IERC721.sol (53 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/IERC721Enumerable.sol (14 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/token/ERC721/IERC721Receiver.sol (25 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol (58 LOC) — TODO
- 0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/utils/Pausable.sol (85 LOC) — TODO
- 0xe2fe530c047f2d85298b07d9333c05737f1435fb/Contract.sol (341 LOC) — TODO

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
