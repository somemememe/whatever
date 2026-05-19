You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/bbt/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x3541499cda8ca51b24724bb8e7ce569727406e04/@openzeppelin/contracts/access/Ownable.sol (100 LOC) — TODO
- 0x3541499cda8ca51b24724bb8e7ce569727406e04/@openzeppelin/contracts/interfaces/IERC1967.sol (24 LOC) — TODO
- 0x3541499cda8ca51b24724bb8e7ce569727406e04/@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol (40 LOC) — TODO
- 0x3541499cda8ca51b24724bb8e7ce569727406e04/@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol (193 LOC) — TODO
- 0x3541499cda8ca51b24724bb8e7ce569727406e04/@openzeppelin/contracts/proxy/Proxy.sol (69 LOC) — TODO
- 0x3541499cda8ca51b24724bb8e7ce569727406e04/@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol (57 LOC) — TODO
- 0x3541499cda8ca51b24724bb8e7ce569727406e04/@openzeppelin/contracts/proxy/beacon/IBeacon.sol (16 LOC) — TODO
- 0x3541499cda8ca51b24724bb8e7ce569727406e04/@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol (70 LOC) — TODO
- 0x3541499cda8ca51b24724bb8e7ce569727406e04/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol (45 LOC) — TODO
- 0x3541499cda8ca51b24724bb8e7ce569727406e04/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol (116 LOC) — TODO
- 0x3541499cda8ca51b24724bb8e7ce569727406e04/@openzeppelin/contracts/utils/Address.sol (159 LOC) — TODO
- 0x3541499cda8ca51b24724bb8e7ce569727406e04/@openzeppelin/contracts/utils/Context.sol (28 LOC) — TODO
- 0x3541499cda8ca51b24724bb8e7ce569727406e04/@openzeppelin/contracts/utils/StorageSlot.sol (135 LOC) — TODO
- 0x74463ed91bfa45bca06d59e8b383a89709842f69/@openzeppelin/contracts/interfaces/draft-IERC6093.sol (161 LOC) — TODO
- 0x74463ed91bfa45bca06d59e8b383a89709842f69/@openzeppelin/contracts/token/ERC20/IERC20.sol (79 LOC) — TODO
- 0x74463ed91bfa45bca06d59e8b383a89709842f69/@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol (26 LOC) — TODO
- 0x74463ed91bfa45bca06d59e8b383a89709842f69/@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol (119 LOC) — TODO
- 0x74463ed91bfa45bca06d59e8b383a89709842f69/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol (228 LOC) — TODO
- 0x74463ed91bfa45bca06d59e8b383a89709842f69/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol (341 LOC) — TODO
- 0x74463ed91bfa45bca06d59e8b383a89709842f69/@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol (45 LOC) — TODO
- 0x74463ed91bfa45bca06d59e8b383a89709842f69/@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol (34 LOC) — TODO
- 0x74463ed91bfa45bca06d59e8b383a89709842f69/contracts/token/BBTOKENv2.sol (75 LOC) — TODO
- 0x74463ed91bfa45bca06d59e8b383a89709842f69/contracts/utils/Registry.sol (35 LOC) — TODO

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
