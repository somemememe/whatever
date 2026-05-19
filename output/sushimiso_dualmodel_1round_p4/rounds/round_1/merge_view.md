# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | Batched ETH commitments can reuse one `msg.value` multiple times | codex_1:0.757 Batched ETH bids can reuse a single `msg.value` to mint multiple commitments |
| F-002 | rewritten_agent_signal | High | medium | codex_1,opencode_1 | Anyone can front-run initialization of an uninitialized auction and seize admin/proceeds control | codex_1:0.727 Any first caller can initialize an uninitialized auction and seize admin and wallet control |
| F-003 | rewritten_agent_signal | Medium | medium | codex_1 | The auction accounts for nominal transfer amounts instead of actual tokens received | codex_1:0.764 The auction books nominal token amounts instead of actual received amounts |
| F-004 | rewritten_agent_signal | Medium | medium | opencode_1 | Admin can redirect auction proceeds after users have already committed | opencode_1:0.403 Arbitrary wallet change after auction commitments |

## Rejection Reasons
- other: 8

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Inconsistent use of nonReentrant modifier | Generic pattern only; no concrete reentrant exploit is supported by the code, and the cited unguarded functions do not expose a realistic permissionless reentrancy path with protocol-level harm. |
| other | opencode_1 | Division by zero in price calculation functions | Initialized auctions enforce `_minimumPrice > 0` in both `initAuction()` and `setAuctionPrice()`, so `clearingPrice()` cannot be zero in the live configuration this contract permits. |
| other | opencode_1 | Deprecated Solidity version 0.6.12 | Using an older compiler version is not, by itself, a concrete reportable vulnerability in this codebase. |
| other | opencode_1 | Outdated `.transfer()` pattern for ETH transfers | The cited `_tokenPayment()` helper is unused; live ETH payouts use `_safeTransferETH`, and the direct `transfer` in `commitEth()` only refunds the caller-chosen beneficiary within the same transaction. |
| other | opencode_1 | Comment and code discrepancy for finalizeTimeExpired | Documentation mismatch only; it does not create a realistic exploit or protocol-level harm. |
| other | opencode_1 | Wallet address can trigger finalization | Allowing the configured payout wallet to finalize does not bypass the existing success/timeout conditions and does not by itself create a theft or insolvency vector. |
| other | opencode_1 | IERC20 interface requires permit which many tokens lack | `permitToken()` is an optional helper; calling it against a token without `permit()` only reverts that caller's own transaction and does not endanger auction funds or state. |
| other | opencode_1 | Missing validation for pointList contract | This is an admin-only misconfiguration risk; the admin already controls whether the point list is enabled, so no permissionless exploit or unexpected asset loss is shown. |
