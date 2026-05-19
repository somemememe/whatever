You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/astrid/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts/security/ReentrancyGuard.sol (77 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts/token/ERC20/IERC20.sol (78 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol (60 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol (143 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts/utils/Address.sol (244 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts/utils/math/SafeMath.sol (215 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol (261 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol (88 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/interfaces/IERC1967Upgradeable.sol (26 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/interfaces/draft-IERC1822Upgradeable.sol (20 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/proxy/ERC1967/ERC1967UpgradeUpgradeable.sol (170 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/proxy/beacon/IBeaconUpgradeable.sol (16 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol (166 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol (112 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol (117 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol (244 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol (37 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/utils/StorageSlotUpgradeable.sol (138 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol (85 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol (42 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol (25 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol (339 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/@openzeppelin/contracts-upgradeable/utils/math/SignedMathUpgradeable.sol (43 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol (566 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/eigenlayer/interfaces/IDelegationManager.sol (81 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/eigenlayer/interfaces/IDelegationTerms.sol (26 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/eigenlayer/interfaces/ISlasher.sol (139 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/eigenlayer/interfaces/IStrategy.sol (91 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/eigenlayer/interfaces/IStrategyManager.sol (259 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/helpers/Utils.sol (36 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/interfaces/IDelegator.sol (46 LOC) — TODO
- 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/interfaces/IRestakedETH.sol (20 LOC) — TODO
- 0xbaa87546cf87b5de1b0b52353a86792d40b8ba70/Contract.sol (690 LOC) — TODO

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
