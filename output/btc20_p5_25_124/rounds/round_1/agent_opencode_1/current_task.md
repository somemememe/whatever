You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/btc20/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x1f006f43f57c45ceb3659e543352b4fae4662df7/@openzeppelin/contracts/access/Ownable.sol (68 LOC) — TODO
- 0x1f006f43f57c45ceb3659e543352b4fae4662df7/@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol (32 LOC) — TODO
- 0x1f006f43f57c45ceb3659e543352b4fae4662df7/@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol (189 LOC) — TODO
- 0x1f006f43f57c45ceb3659e543352b4fae4662df7/@openzeppelin/contracts/proxy/Proxy.sol (83 LOC) — TODO
- 0x1f006f43f57c45ceb3659e543352b4fae4662df7/@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol (61 LOC) — TODO
- 0x1f006f43f57c45ceb3659e543352b4fae4662df7/@openzeppelin/contracts/proxy/beacon/IBeacon.sol (15 LOC) — TODO
- 0x1f006f43f57c45ceb3659e543352b4fae4662df7/@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol (64 LOC) — TODO
- 0x1f006f43f57c45ceb3659e543352b4fae4662df7/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol (77 LOC) — TODO
- 0x1f006f43f57c45ceb3659e543352b4fae4662df7/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol (120 LOC) — TODO
- 0x1f006f43f57c45ceb3659e543352b4fae4662df7/@openzeppelin/contracts/utils/Address.sol (189 LOC) — TODO
- 0x1f006f43f57c45ceb3659e543352b4fae4662df7/@openzeppelin/contracts/utils/Context.sol (24 LOC) — TODO
- 0x1f006f43f57c45ceb3659e543352b4fae4662df7/@openzeppelin/contracts/utils/StorageSlot.sol (83 LOC) — TODO
- 0x1f006f43f57c45ceb3659e543352b4fae4662df7/contracts/import.sol (13 LOC) — TODO
- 0xe69be7d6b306b4fbce516e3f07c8f438a6860084/@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol (95 LOC) — TODO
- 0xe69be7d6b306b4fbce516e3f07c8f438a6860084/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol (138 LOC) — TODO
- 0xe69be7d6b306b4fbce516e3f07c8f438a6860084/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol (117 LOC) — TODO
- 0xe69be7d6b306b4fbce516e3f07c8f438a6860084/@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol (75 LOC) — TODO
- 0xe69be7d6b306b4fbce516e3f07c8f438a6860084/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol (82 LOC) — TODO
- 0xe69be7d6b306b4fbce516e3f07c8f438a6860084/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol (195 LOC) — TODO
- 0xe69be7d6b306b4fbce516e3f07c8f438a6860084/@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol (37 LOC) — TODO
- 0xe69be7d6b306b4fbce516e3f07c8f438a6860084/contracts/ETH/PresaleV5.sol (369 LOC) — TODO

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
