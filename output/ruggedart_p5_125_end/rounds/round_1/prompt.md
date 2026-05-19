You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/ruggedart/src/onchain_auto.

## Contracts in Scope

# Scope

- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts/contracts/access/Ownable.sol (100 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC1822.sol (20 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol (193 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol (16 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts/contracts/token/ERC1155/IERC1155Receiver.sol (59 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol (79 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol (28 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts/contracts/utils/Address.sol (159 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts/contracts/utils/Context.sol (28 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol (84 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol (135 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol (25 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol (119 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol (228 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol (153 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol (34 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol (105 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/universal-router/contracts/interfaces/IRewardsCollector.sol (13 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/universal-router/contracts/interfaces/IUniversalRouter.sol (26 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/lib/universal-router/lib/solmate/src/tokens/ERC20.sol (206 LOC) — TODO
- 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol (306 LOC) — TODO

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
