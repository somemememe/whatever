You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/harvestfinance/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol (31 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol (214 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/@openzeppelin/contracts-upgradeable/proxy/Initializable.sol (55 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol (313 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol (77 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol (75 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol (165 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol (32 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultStorage.sol (196 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV1.sol (380 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV2.sol (111 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/inheritance/ControllableInit.sol (30 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/inheritance/GovernableInit.sol (50 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/inheritance/Storage.sol (35 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/interface/IController.sol (133 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/interface/IERC4626.sol (263 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/interface/IStrategy.sol (37 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/interface/IUpgradeSource.sol (10 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/interface/IVault.sol (58 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/upgradability/ReentrancyGuardUpgradeable.sol (51 LOC) — TODO
- 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/hardhat/console.sol (1552 LOC) — TODO
- 0xf0358e8c3cd5fa238a29301d0bea3d63a17bedbe/Contract.sol (208 LOC) — TODO

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
