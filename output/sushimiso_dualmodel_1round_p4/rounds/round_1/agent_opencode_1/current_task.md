You are auditing the smart contracts in /Users/zhanglongqin/AuditHoundV2/cases/sushimiso/src/onchain_auto.

## Contracts in Scope

# Scope

- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Access/MISOAccessControls.sol (149 LOC) — TODO
- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Access/MISOAdminAccess.sol (73 LOC) — TODO
- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol (720 LOC) — TODO
- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/OpenZeppelin/access/AccessControl.sol (215 LOC) — TODO
- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/OpenZeppelin/utils/Address.sol (188 LOC) — TODO
- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/OpenZeppelin/utils/Context.sol (24 LOC) — TODO
- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/OpenZeppelin/utils/EnumerableSet.sol (296 LOC) — TODO
- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/OpenZeppelin/utils/ReentrancyGuard.sol (62 LOC) — TODO
- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Utils/BoringBatchable.sol (64 LOC) — TODO
- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Utils/BoringERC20.sol (66 LOC) — TODO
- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Utils/BoringMath.sol (88 LOC) — TODO
- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Utils/Documents.sol (101 LOC) — TODO
- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Utils/SafeTransfer.sol (88 LOC) — TODO
- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/interfaces/IERC20.sol (24 LOC) — TODO
- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/interfaces/IMisoMarket.sol (9 LOC) — TODO
- 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/interfaces/IPointList.sol (16 LOC) — TODO

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
