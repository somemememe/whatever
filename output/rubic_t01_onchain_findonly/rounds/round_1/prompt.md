You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/rubic/src.

## Contracts in Scope

# Scope

- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol (260 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol (88 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol (138 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol (117 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol (75 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol (82 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol (60 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol (116 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol (195 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol (37 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol (75 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol (42 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol (25 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol (367 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol (123 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol (444 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/architecture/OnlySourceFunctionality.sol (25 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/errors/Errors.sol (19 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/FullMath.sol (110 LOC) — TODO
- onchain/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol (35 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol (260 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol (88 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol (138 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol (117 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol (75 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol (82 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol (60 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol (116 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol (195 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol (37 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol (75 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol (42 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol (25 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol (367 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/contracts/RubicProxy.sol (127 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/rubic-bridge-base/contracts/BridgeBase.sol (457 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/rubic-bridge-base/contracts/architecture/OnlySourceFunctionality.sol (25 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/rubic-bridge-base/contracts/errors/Errors.sol (19 LOC) — TODO
- onchain/0x33388cf69e032c6f60a420b37e44b1f5443d3333/rubic-bridge-base/contracts/libraries/FullMath.sol (110 LOC) — TODO

# Notes

- Auto-generated file-level map.
- Descriptions are placeholders and can be edited later.
- Included in direct audit scope: onchain/**
- Excluded from direct audit scope: out/**, **/_baseline_excluded/**, FlawVerifier.sol, interface.sol


## Included Direct Audit Scope

Only keep findings whose root cause location is inside files matching:
- `onchain/**`

You may still read other files in the target directory for context, but do not report them as root cause locations.


## Excluded From Direct Audit Scope

Do not report findings whose root cause exists solely in files matching:
- `out/**`
- `**/_baseline_excluded/**`
- `FlawVerifier.sol`
- `interface.sol`

You may still read those files when they define interfaces, structs, errors, or external integration context used by in-scope implementation files.


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
