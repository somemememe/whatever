You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/hypr/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x40c31236b228935b0329eff066b1ad96e319595e/contracts/legacy/L1ChugSplashProxy.sol (289 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol (138 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol (383 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol (82 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol (28 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/draft-IERC20Permit.sol (60 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol (116 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/openzeppelin-contracts/contracts/utils/Address.sol (222 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/openzeppelin-contracts/contracts/utils/Context.sol (24 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/openzeppelin-contracts/contracts/utils/Strings.sol (75 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/openzeppelin-contracts/contracts/utils/introspection/ERC165Checker.sol (123 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol (25 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/openzeppelin-contracts/contracts/utils/math/Math.sol (226 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol (43 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol (138 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/openzeppelin-contracts-upgradeable/contracts/utils/AddressUpgradeable.sol (195 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/lib/solmate/src/utils/FixedPointMathLib.sol (366 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/L1/L1StandardBridge.sol (315 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/L1/ResourceMetering.sol (160 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/libraries/Arithmetic.sol (28 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/libraries/Burn.sol (32 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/libraries/Constants.sol (46 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/libraries/Encoding.sol (136 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/libraries/Hashing.sol (124 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/libraries/Predeploys.sol (77 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/libraries/SafeCall.sol (142 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/libraries/Types.sol (70 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/libraries/rlp/RLPWriter.sol (163 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/CrossDomainMessenger.sol (379 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/IOptimismMintableERC20.sol (31 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/OptimismMintableERC20.sol (123 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/Semver.sol (40 LOC) — TODO
- 0xe468b43b4ae4d750cd6a5d7edacc1a751302c99c/src/universal/StandardBridge.sol (475 LOC) — TODO

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
