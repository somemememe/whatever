You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/wiselending02/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/Babylonian.sol (56 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/InterfaceHub/IAaveHubLite.sol (11 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/InterfaceHub/IERC20.sol (75 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/InterfaceHub/IFeeManagerLight.sol (10 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/InterfaceHub/IPositionNFTs.sol (92 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/InterfaceHub/IWETH.sol (17 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/InterfaceHub/IWiseOracleHub.sol (90 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/InterfaceHub/IWiseSecurity.sol (200 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol (1185 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/OwnableMaster.sol (124 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/PoolManager.sol (277 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/TransferHub/CallOptionalReturn.sol (39 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/TransferHub/TransferHelper.sol (52 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol (602 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol (1558 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLendingDeclaration.sol (381 LOC) — TODO
- 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLowLevelHelper.sol (450 LOC) — TODO

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
