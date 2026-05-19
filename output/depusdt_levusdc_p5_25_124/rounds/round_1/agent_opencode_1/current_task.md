You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/depusdt_levusdc/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x7b190a928aa76eece5cb3e0f6b3bdb24fcdd9b4f/@openzeppelin/contracts/access/Ownable.sol (68 LOC) — TODO
- 0x7b190a928aa76eece5cb3e0f6b3bdb24fcdd9b4f/@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol (32 LOC) — TODO
- 0x7b190a928aa76eece5cb3e0f6b3bdb24fcdd9b4f/@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol (189 LOC) — TODO
- 0x7b190a928aa76eece5cb3e0f6b3bdb24fcdd9b4f/@openzeppelin/contracts/proxy/Proxy.sol (83 LOC) — TODO
- 0x7b190a928aa76eece5cb3e0f6b3bdb24fcdd9b4f/@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol (61 LOC) — TODO
- 0x7b190a928aa76eece5cb3e0f6b3bdb24fcdd9b4f/@openzeppelin/contracts/proxy/beacon/IBeacon.sol (15 LOC) — TODO
- 0x7b190a928aa76eece5cb3e0f6b3bdb24fcdd9b4f/@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol (64 LOC) — TODO
- 0x7b190a928aa76eece5cb3e0f6b3bdb24fcdd9b4f/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol (77 LOC) — TODO
- 0x7b190a928aa76eece5cb3e0f6b3bdb24fcdd9b4f/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol (120 LOC) — TODO
- 0x7b190a928aa76eece5cb3e0f6b3bdb24fcdd9b4f/@openzeppelin/contracts/utils/Address.sol (189 LOC) — TODO
- 0x7b190a928aa76eece5cb3e0f6b3bdb24fcdd9b4f/@openzeppelin/contracts/utils/Context.sol (24 LOC) — TODO
- 0x7b190a928aa76eece5cb3e0f6b3bdb24fcdd9b4f/@openzeppelin/contracts/utils/StorageSlot.sol (83 LOC) — TODO
- 0x7b190a928aa76eece5cb3e0f6b3bdb24fcdd9b4f/contracts/import.sol (13 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol (165 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol (219 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/CurveContractInterface.sol (15 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/CurveSwap.sol (64 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/DepErc20.sol (217 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/DepToken.sol (1225 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/DepTokenInterfaces.sol (259 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/DepositWithdraw.sol (95 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/DepositWithdrawInterface.sol (35 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/EIP20Interface.sol (63 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/EIP20NonStandardInterface.sol (71 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/ErrorReporter.sol (132 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/ExponentialNoError.sol (171 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/InterestRateModel.sol (27 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/LevTokenInterfaces.sol (227 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/MatrixpricerInterface.sol (20 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/TensorpricerInterface.sol (24 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/vendor/interfaces/Address.sol (244 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/vendor/interfaces/IAddressProvider.sol (10 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/vendor/interfaces/ICurveFi.sol (7 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/vendor/interfaces/IERC20.sol (82 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/vendor/interfaces/IRegistry.sol (12 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/contracts/vendor/interfaces/SafeERC20.sol (115 LOC) — TODO
- 0x94290106d2a32bc89be9f1c3a3f3394f64578aa6/hardhat/console.sol (1532 LOC) — TODO

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
