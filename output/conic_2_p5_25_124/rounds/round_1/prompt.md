You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/conic_2/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x635228edaead8a76b6ae1779bd7682043321943d/Address.sol (244 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/ConvexHandlerV3.sol (151 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/CurvePoolUtils.sol (69 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/IBaseRewardPool.sol (28 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/IBooster.sol (32 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/IConicPool.sol (135 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/IController.sol (89 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/IConvexHandler.sol (19 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/ICurvePoolV1.sol (82 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/ICurvePoolV2.sol (88 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/ICurveRegistryCache.sol (49 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/IERC20.sol (82 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/IERC20Metadata.sol (28 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/IInflationManager.sol (53 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/ILpToken.sol (10 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/ILpTokenStaker.sol (38 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/IOracle.sol (12 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/IOwnable.sol (10 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/IRewardManager.sol (38 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/IRewardStaking.sol (28 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/SafeERC20.sol (116 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/ScaledMath.sol (123 LOC) — TODO
- 0x635228edaead8a76b6ae1779bd7682043321943d/draft-IERC20Permit.sol (60 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/Address.sol (244 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ArrayExtensions.sol (12 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol (899 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/Context.sol (24 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/CurvePoolUtils.sol (69 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ERC20.sol (389 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/EnumerableMap.sol (530 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/EnumerableSet.sol (378 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/IBaseRewardPool.sol (28 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/IBooster.sol (32 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ICNCLockerV2.sol (78 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/IConicPool.sol (134 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/IController.sol (89 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/IConvexHandler.sol (19 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ICurveHandlerV3.sol (12 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ICurvePoolV1.sol (82 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ICurvePoolV2.sol (88 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ICurveRegistryCache.sol (51 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/IERC20.sol (82 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/IERC20Metadata.sol (28 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/IInflationManager.sol (53 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ILpToken.sol (10 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ILpTokenStaker.sol (38 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/IOracle.sol (12 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/IRewardManager.sol (38 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/Initializable.sol (165 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/LpToken.sol (42 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/MerkleProof.sol (28 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/Ownable.sol (83 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol (474 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/SafeERC20.sol (116 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ScaledMath.sol (123 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/UniswapRouter02.sol (76 LOC) — TODO
- 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/draft-IERC20Permit.sol (60 LOC) — TODO

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
