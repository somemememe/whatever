You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/alkimiya_io/src.

## Contracts in Scope

# Scope

- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol (908 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/interfaces/ISilicaIndex.sol (77 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/interfaces/ISilicaPools.sol (447 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/access/Ownable.sol (100 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol (59 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/interfaces/IERC5267.sol (28 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol (161 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol (468 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol (127 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol (59 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol (20 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol (316 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol (79 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol (26 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol (90 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol (118 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/utils/Address.sol (159 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/utils/Arrays.sol (127 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/utils/Context.sol (28 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol (84 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/utils/ShortStrings.sol (123 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol (135 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/utils/Strings.sol (94 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol (174 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol (160 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol (86 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol (27 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol (25 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/utils/math/Math.sol (415 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol (1153 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol (43 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/lib/solady/src/utils/FixedPointMathLib.sol (1161 LOC) — TODO
- onchain_auto/0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/libraries/PoolMaths.sol (130 LOC) — TODO
- onchain_auto/src/FlawVerifier.sol (360 LOC) — TODO

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
