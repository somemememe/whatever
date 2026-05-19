You are auditing the smart contracts in /Users/lu/Desktop/Red_V1G/2025-05-dodo-cross-chain-dex/omni-chain-contracts/contracts.

## Contracts in Scope

# Scope

- GatewayCrossChain.sol (634 LOC) — TODO
- GatewaySend.sol (409 LOC) — TODO
- GatewayTransferNative.sol (705 LOC) — TODO
- interfaces/IDODORouteProxy.sol (19 LOC) — TODO
- interfaces/IUniswapV2Factory.sol (18 LOC) — TODO
- interfaces/IUniswapV2Router01.sol (96 LOC) — TODO
- interfaces/IWETH9.sol (30 LOC) — TODO
- interfaces/IZRC20.sol (11 LOC) — TODO
- libraries/AccountEncoder.sol (54 LOC) — TODO
- libraries/BytesHelperLib.sol (41 LOC) — TODO
- libraries/SafeMath.sol (17 LOC) — TODO
- libraries/SwapDataHelperLib.sol (273 LOC) — TODO
- libraries/TransferHelper.sol (28 LOC) — TODO
- libraries/UniswapV2Library.sol (95 LOC) — TODO

# Notes

- Auto-generated file-level map.
- Descriptions are placeholders and can be edited later.
- Excluded from direct audit scope: mocks/**



## Excluded From Direct Audit Scope

Do not report findings whose root cause exists solely in files matching:
- `mocks/**`

You may still read those files when they define interfaces, structs, errors, or external integration context used by in-scope implementation files.


## Known Findings (do not duplicate)

- F-001: User-controlled swap params can spend arbitrary token balances held by gateway contracts (Critical, high)
- F-002: Refunds for non-20-byte recipients are claimable by anyone (Critical, high)
- F-003: Bitcoin/non-EVM revert recipient is truncated to 20 bytes, misdirecting refunds (High, high)
- F-004: withdrawToNativeChain trusts nominal input amount and can execute underfunded withdrawals from contract reserves (Critical, high)
- F-005: GatewaySend destination onCall trusts payload amount/token data and can drain contract reserves (Critical, high)
- F-006: Reentrancy in `GatewayTransferNative.claimRefund` allows repeated refund claims (Medium, medium)
- F-007: Balance-based pair existence check can be dust-poisoned into swap-path DoS (Medium, medium)
- F-008: Public `withdraw` can be abused when residual gateway allowances remain (Medium, low)
- F-009: Empty `swapDataZ` path allows cross-asset withdrawals without performing conversion (Critical, high)
- F-010: GatewaySend source flow does not bind bridged asset to swap output asset (Critical, high)
- F-011: Refund records can be overwritten in callback handlers (Medium, medium)
- F-012: AccountEncoder.decompressAccounts builds invalid memory layout for `Account[]` (Medium, high)
- F-013: Recipient bytes are silently truncated/padded into EVM addresses in payout paths (Medium, medium)
- F-014: GatewaySend direct ERC20 source deposit uses nominal amount and can spend reserves on underfunded transfer-in (High, medium)
- F-015: GatewaySend destination finalizes success even when ERC20 payout transfer fails softly (Medium, high)
- F-016: GatewaySend ETH payout uses `.transfer` and can DoS smart-contract recipients (Low, high)
- F-017: GatewaySend revert handler lacks native-asset refund path and can strand reverted ETH (High, high)
- F-018: Swap output asset is not bound to target payout token before withdrawal/transfer (Critical, high)
- F-022: `amountInMax`-based post-swap check can cause avoidable withdrawal reverts (Medium, medium)

## Optional Prior Round Summary

An optional prior round summary is available at:
- `/Users/lu/Desktop/Red_V1G/AuditHoundV2/output/dodo_contracts_no_mocks_3r/rounds/round_5/round_summary.md`

Read it only if useful, and think it before you use it.It may not be very concise.


## Optional Global Audit Memory

An optional global audit memory is available at:
- `/Users/lu/Desktop/Red_V1G/AuditHoundV2/output/dodo_contracts_no_mocks_3r/global_summary.md`

Read it only if useful. It is historical context, not a coverage guarantee,
not proof that any area is safe, and not a priority list.


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
