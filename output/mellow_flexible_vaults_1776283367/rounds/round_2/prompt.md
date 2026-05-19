You are auditing the smart contracts in /Users/lu/Desktop/Red_V1G/2025-07-mellow-flexible-vaults/flexible-vaults/src.

## Contracts in Scope

# Scope

- factories/Factory.sol (131 LOC) — TODO
- hooks/BasicRedeemHook.sol (42 LOC) — TODO
- hooks/LidoDepositHook.sol (49 LOC) — TODO
- hooks/RedirectingDepositHook.sol (27 LOC) — TODO
- libraries/FenwickTreeLibrary.sol (130 LOC) — TODO
- libraries/ShareManagerFlagLibrary.sol (76 LOC) — TODO
- libraries/SlotLibrary.sol (20 LOC) — TODO
- libraries/TransferLibrary.sol (49 LOC) — TODO
- managers/BasicShareManager.sol (72 LOC) — TODO
- managers/FeeManager.sol (177 LOC) — TODO
- managers/RiskManager.sol (263 LOC) — TODO
- managers/ShareManager.sol (264 LOC) — TODO
- managers/TokenizedShareManager.sol (56 LOC) — TODO
- modules/ACLModule.sol (22 LOC) — TODO
- modules/BaseModule.sol (32 LOC) — TODO
- modules/CallModule.sol (20 LOC) — TODO
- modules/ShareModule.sol (323 LOC) — TODO
- modules/SubvaultModule.sol (49 LOC) — TODO
- modules/VaultModule.sol (172 LOC) — TODO
- modules/VerifierModule.sol (39 LOC) — TODO
- oracles/Oracle.sol (248 LOC) — TODO
- permissions/BitmaskVerifier.sol (76 LOC) — TODO
- permissions/Consensus.sol (131 LOC) — TODO
- permissions/MellowACL.sol (64 LOC) — TODO
- permissions/Verifier.sol (180 LOC) — TODO
- permissions/protocols/ERC20Verifier.sol (44 LOC) — TODO
- permissions/protocols/EigenLayerVerifier.sol (132 LOC) — TODO
- permissions/protocols/OwnedCustomVerifier.sol (30 LOC) — TODO
- permissions/protocols/SymbioticVerifier.sol (88 LOC) — TODO
- queues/DepositQueue.sol (202 LOC) — TODO
- queues/Queue.sol (70 LOC) — TODO
- queues/RedeemQueue.sol (248 LOC) — TODO
- queues/SignatureDepositQueue.sol (24 LOC) — TODO
- queues/SignatureQueue.sol (153 LOC) — TODO
- queues/SignatureRedeemQueue.sol (28 LOC) — TODO
- strategies/SymbioticStrategy.sol (65 LOC) — TODO
- vaults/Subvault.sol (20 LOC) — TODO
- vaults/Vault.sol (55 LOC) — TODO
- vaults/VaultConfigurator.sol (74 LOC) — TODO

# Notes

- Auto-generated file-level map.
- Descriptions are placeholders and can be edited later.
- Excluded from direct audit scope: interfaces/**


## Excluded From Direct Audit Scope

Do not report findings whose root cause exists solely in files matching:
- `interfaces/**`

You may still read those files when they define interfaces, structs, errors, or external integration context used by in-scope implementation files.


## Known Findings (do NOT repeat — find NEW issues)

- F-001: Consensus threshold can be bypassed with duplicated signer entries (Critical, high)
- F-002: Deposit cancellation uses oracle checkpoint value as Fenwick index (High, high)
- F-003: Transfer whitelist check is inverted (High, high)
- F-004: Signature queues bypass global queue pause (Medium, high)
- F-005: Auto-claim on token updates can become gas-prohibitive with many queues/assets (Medium, medium)
- F-006: Permissionless one-time `setVault` can be initialization-hijacked in non-atomic deployments (Low, medium)

## Optional Prior Round Summary

An optional prior round summary is available at:
- `/Users/lu/Desktop/Red_V1G/AuditHoundV2/output/mellow_flexible_vaults_1776283367/rounds/round_1/round_summary.md`

Read it only if useful, and think it before you use it.It may not be very concise.


## Optional Global Audit Memory

An optional global audit memory is available at:
- `/Users/lu/Desktop/Red_V1G/AuditHoundV2/output/mellow_flexible_vaults_1776283367/global_summary.md`

Read it only if useful. It is historical context, not a coverage guarantee,
not proof that any area is safe, and not a priority list.


## Task

Find security vulnerabilities in the contracts listed above as more as you can.And there are lots of high and medium vulns.

You should look for:
- vulnerabilities
- reportable issues

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
