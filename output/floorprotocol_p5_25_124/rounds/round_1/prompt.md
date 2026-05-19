You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/floorprotocol/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x49ad262c49c7aa708cc2df262ed53b64a17dd5ee/solc_0.8/openzeppelin/interfaces/draft-IERC1822.sol (20 LOC) — TODO
- 0x49ad262c49c7aa708cc2df262ed53b64a17dd5ee/solc_0.8/openzeppelin/proxy/ERC1967/ERC1967Proxy.sol (33 LOC) — TODO
- 0x49ad262c49c7aa708cc2df262ed53b64a17dd5ee/solc_0.8/openzeppelin/proxy/ERC1967/ERC1967Upgrade.sol (182 LOC) — TODO
- 0x49ad262c49c7aa708cc2df262ed53b64a17dd5ee/solc_0.8/openzeppelin/proxy/Proxy.sol (86 LOC) — TODO
- 0x49ad262c49c7aa708cc2df262ed53b64a17dd5ee/solc_0.8/openzeppelin/proxy/beacon/IBeacon.sol (16 LOC) — TODO
- 0x49ad262c49c7aa708cc2df262ed53b64a17dd5ee/solc_0.8/openzeppelin/utils/Address.sol (222 LOC) — TODO
- 0x49ad262c49c7aa708cc2df262ed53b64a17dd5ee/solc_0.8/openzeppelin/utils/StorageSlot.sol (84 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@openzeppelin/contracts/interfaces/draft-IERC1822.sol (20 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol (193 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@openzeppelin/contracts/proxy/beacon/IBeacon.sol (16 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol (59 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@openzeppelin/contracts/token/ERC20/IERC20.sol (79 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@openzeppelin/contracts/token/ERC721/IERC721.sol (135 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol (28 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@openzeppelin/contracts/utils/Address.sol (159 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@openzeppelin/contracts/utils/StorageSlot.sol (135 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@openzeppelin/contracts/utils/introspection/IERC165.sol (25 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol (228 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol (153 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@permit2/src/interfaces/IAllowanceTransfer.sol (165 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@permit2/src/interfaces/IEIP712.sol (6 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@permit2/src/interfaces/IPermit2.sol (11 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@permit2/src/interfaces/ISignatureTransfer.sol (134 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@uniswap/universal-router/contracts/interfaces/IRewardsCollector.sol (13 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol (26 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/solmate/src/tokens/ERC20.sol (206 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/Constants.sol (446 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/Errors.sol (42 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/FloorGetter.sol (541 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/FloorPeriphery.sol (422 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/base/Multicall.sol (43 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/interface/IFlooring.sol (311 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/interface/IFragmentToken.sol (10 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/interface/IMulticall.sol (18 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/interface/IWETH9.sol (13 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/library/CurrencyTransfer.sol (104 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/library/ERC721Transfer.sol (79 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/library/OwnedUpgradeable.sol (33 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/logic/CollectionKey.sol (88 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/logic/SafeBox.sol (49 LOC) — TODO
- 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/logic/Structs.sol (215 LOC) — TODO

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
