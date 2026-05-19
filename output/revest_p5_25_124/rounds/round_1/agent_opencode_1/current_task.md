You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/revest/src.

## Contracts in Scope

# Scope

- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/access/AccessControl.sol (250 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/access/AccessControlEnumerable.sol (87 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/access/Ownable.sol (71 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/security/ReentrancyGuard.sol (62 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/token/ERC1155/ERC1155.sol (451 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/token/ERC1155/IERC1155.sol (124 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol (52 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol (21 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/token/ERC20/IERC20.sol (81 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol (98 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/utils/Address.sol (210 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/utils/Context.sol (23 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/utils/Strings.sol (66 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/utils/introspection/ERC165.sol (28 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/utils/introspection/ERC165Checker.sol (112 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/utils/introspection/IERC165.sol (24 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/@openzeppelin/contracts/utils/structs/EnumerableSet.sol (294 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/FNFTHandler.sol (127 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/Revest.sol (409 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/IAddressLock.sol (59 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/IAddressRegistry.sol (66 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/IFNFTHandler.sol (24 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/IInterestHandler.sol (28 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/ILockManager.sol (24 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/IMetadataHandler.sol (24 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/IOracleDispatch.sol (51 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/IOutputReceiver.sol (29 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/IRegistryProvider.sol (15 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/IRevest.sol (165 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/IRevestToken.sol (9 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/IRewardsHandler.sol (25 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/ITokenVault.sol (52 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/lib/IUnicryptV2Locker.sol (134 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/lib/IWETH.sol (9 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/lib/uniswap/IUniswapV2Factory.sol (23 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/utils/RevestAccessControl.sol (85 LOC) — TODO
- 0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/utils/RevestReentrancyGuard.sol (24 LOC) — TODO

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
