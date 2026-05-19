You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/particletrade/src/onchain_auto.

## Contracts in Scope

# Scope

- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/contracts/interfaces/IParticleExchange.sol (322 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/contracts/libraries/math/MathUtils.sol (50 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/contracts/libraries/security/ReentrancyGuard.sol (73 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/contracts/libraries/types/Errors.sol (23 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/contracts/libraries/types/Structs.sol (13 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/contracts/protocol/ParticleExchange.sol (1162 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol (6 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol (145 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts/contracts/utils/Address.sol (244 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts/contracts/utils/Multicall.sol (24 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol (25 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol (71 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol (95 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC1967Upgradeable.sol (26 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts-upgradeable/contracts/interfaces/draft-IERC1822Upgradeable.sol (20 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts-upgradeable/contracts/proxy/ERC1967/ERC1967UpgradeUpgradeable.sol (198 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts-upgradeable/contracts/proxy/beacon/IBeaconUpgradeable.sol (16 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol (165 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol (108 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts-upgradeable/contracts/utils/AddressUpgradeable.sol (219 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol (37 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/openzeppelin-contracts-upgradeable/contracts/utils/StorageSlotUpgradeable.sol (88 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/solmate/src/tokens/ERC20.sol (206 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/solmate/src/tokens/WETH.sol (35 LOC) — TODO
- 0xe4764f9cd8ecc9659d3abf35259638b20ac536e4/lib/solmate/src/utils/SafeTransferLib.sol (128 LOC) — TODO

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
