You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/cream/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x2db6c82ce72c8d7d770ba1b5f5ed0b6e075066d6/contracts/CErc20Delegator.sol (476 LOC) — TODO
- 0x2db6c82ce72c8d7d770ba1b5f5ed0b6e075066d6/contracts/CTokenInterfaces.sol (302 LOC) — TODO
- 0x2db6c82ce72c8d7d770ba1b5f5ed0b6e075066d6/contracts/ComptrollerInterface.sol (71 LOC) — TODO
- 0x2db6c82ce72c8d7d770ba1b5f5ed0b6e075066d6/contracts/InterestRateModel.sol (30 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CCollateralCapErc20CheckRepay.sol (812 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CCollateralCapErc20CheckRepayDelegate.sol (52 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CToken.sol (1211 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CTokenCheckRepay.sol (1230 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CTokenInterfaces.sol (494 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CarefulMath.sol (88 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/ComptrollerInterface.sol (147 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/ComptrollerStorage.sol (156 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/EIP20Interface.sol (68 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/EIP20NonStandardInterface.sol (73 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/ERC3156FlashBorrowerInterface.sol (20 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/ERC3156FlashLenderInterface.sol (33 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/ErrorReporter.sol (191 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/Exponential.sol (457 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/InterestRateModel.sol (38 LOC) — TODO
- 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/PriceOracle/PriceOracle.sol (16 LOC) — TODO

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
