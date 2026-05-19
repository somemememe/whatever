You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/pawnfi/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol (260 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol (88 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol (165 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol (81 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol (82 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol (60 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol (116 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol (27 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol (145 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol (41 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol (219 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol (37 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol (70 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol (42 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol (25 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol (345 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol (378 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/contracts/ApeStaking.sol (773 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/contracts/ApeStakingStorage.sol (150 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/contracts/interfaces/IApeCoinStaking.sol (224 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/contracts/interfaces/IApePool.sol (115 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/contracts/interfaces/INftGateway.sol (9 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/contracts/interfaces/IPTokenApeStaking.sol (33 LOC) — TODO
- 0x85018cf6f53c8bbd03c3137e71f4fca226cda92c/contracts/interfaces/ITokenLending.sol (9 LOC) — TODO

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
