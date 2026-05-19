You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/usual_money/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x35d8949372d46b7a3d5a56006ae77b215fc69bc0/lib/openzeppelin-contracts/contracts/access/Ownable.sol (100 LOC) — TODO
- 0x35d8949372d46b7a3d5a56006ae77b215fc69bc0/lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol (24 LOC) — TODO
- 0x35d8949372d46b7a3d5a56006ae77b215fc69bc0/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol (40 LOC) — TODO
- 0x35d8949372d46b7a3d5a56006ae77b215fc69bc0/lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol (193 LOC) — TODO
- 0x35d8949372d46b7a3d5a56006ae77b215fc69bc0/lib/openzeppelin-contracts/contracts/proxy/Proxy.sol (69 LOC) — TODO
- 0x35d8949372d46b7a3d5a56006ae77b215fc69bc0/lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol (16 LOC) — TODO
- 0x35d8949372d46b7a3d5a56006ae77b215fc69bc0/lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol (45 LOC) — TODO
- 0x35d8949372d46b7a3d5a56006ae77b215fc69bc0/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol (116 LOC) — TODO
- 0x35d8949372d46b7a3d5a56006ae77b215fc69bc0/lib/openzeppelin-contracts/contracts/utils/Address.sol (159 LOC) — TODO
- 0x35d8949372d46b7a3d5a56006ae77b215fc69bc0/lib/openzeppelin-contracts/contracts/utils/Context.sol (28 LOC) — TODO
- 0x35d8949372d46b7a3d5a56006ae77b215fc69bc0/lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol (135 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol (98 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlDefaultAdminRules.sol (192 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts/contracts/interfaces/IERC5267.sol (28 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol (161 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol (79 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol (26 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol (90 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol (118 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts/contracts/utils/Address.sol (159 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts/contracts/utils/Strings.sol (94 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol (174 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol (86 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts/contracts/utils/math/Math.sol (415 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol (43 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol (228 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol (341 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PausableUpgradeable.sol (40 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol (88 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol (34 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts-upgradeable/contracts/utils/NoncesUpgradeable.sol (66 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol (140 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol (105 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol (210 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/constants.sol (249 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/errors.sol (142 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/interfaces/IDaoCollateral.sol (259 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/interfaces/registry/IRegistryAccess.sol (18 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/interfaces/registry/IRegistryContract.sol (28 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/interfaces/token/IRTUsd0.sol (32 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/interfaces/token/IUsd0.sol (62 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/interfaces/token/IUsd0PP.sol (235 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/interfaces/token/IUsual.sol (63 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/token/Usd0PP.sol (597 LOC) — TODO
- 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/utils/CheckAccessControl.sol (19 LOC) — TODO

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
