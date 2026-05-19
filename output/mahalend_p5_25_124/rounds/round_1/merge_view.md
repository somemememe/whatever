# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 11

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | Flash-loan debt opening reuses a stale eMode category after the callback | codex_1:1.0 Flash-loan debt opening reuses a stale eMode category after the callback |
| F-002 | exact_agent_candidate | Medium | high | codex_1 | Full liquidation with protocol fees can leave the collateral bit permanently stuck on | codex_1:1.0 Full liquidation with protocol fees can leave the collateral bit permanently stuck on |
| F-003 | rewritten_agent_signal | High | high | codex_1 | Reserve accounting trusts nominal transfer amounts instead of actual received amounts | codex_1:0.741 Transfers are accounted by requested amount instead of actual received amount |

## Rejection Reasons
- other: 9
- trust_or_owner_model: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Non-collateral assets are automatically marked as collateral on first receipt | The code does set the collateral bit for first-time receipt even when `liquidationThreshold == 0`, but those assets are ignored in account-data and liquidation calculations, and the holder can clear the flag while the balance exists. This is a state-integrity/UX issue, not a realistic protocol-level loss or lockup. |
| trust_or_owner_model | opencode_1 | Liquidation Bonus of Zero Causes Permanent Liquidation Failure | This requires a privileged, nonsensical reserve configuration. Governance/configurator can already brick a market with invalid parameters; the report does not show an unprivileged exploit or a bug reachable under normal reserve setup. |
| other | opencode_1 | Integer Overflow in Isolation Mode Debt Calculation | The addition is checked by Solidity 0.8 and the increment is narrowed with `toUint128()`, so overflow reverts rather than wraps. The configured isolation debt ceiling is also far below `uint128` range, so the claimed bypass is not feasible. |
| other | opencode_1 | Price Oracle Manipulation Risk | This is a generic single-oracle trust assumption, not a code-specific vulnerability in this codebase. No concrete oracle integration flaw or exploitable invariant break was identified. |
| other | opencode_1 | Unchecked Callback in Flash Loan Enables Complex Reentrancy | Flash-loan callbacks are intentional, and the implementation explicitly reorders state transitions to tolerate the callback. Without a concrete broken invariant or exploit path, generic reentrancy composability is not reportable. |
| other | opencode_1 | Rounding Error in Liquidation Can Cause Dust Amounts | This is ordinary integer rounding dust with no concrete path to meaningful fund loss, lockup, or protocol insolvency. |
| other | opencode_1 | Division Before Multiplication Causes Precision Loss | The cited arithmetic introduces only normal integer rounding and no demonstrated way to cross collateral or liquidation thresholds in a materially exploitable way. |
| other | opencode_1 | Stable Debt Rebalance Rate Manipulation | Permissionless stable-rate rebalancing is intended behavior and is gated by `validateRebalanceStableBorrowRate`. The report describes expected economic behavior, not a violation of protocol invariants. |
| other | opencode_1 | Uninitialized Reserve Can Be Reinitialized | `ReserveLogic.init` runs atomically and permanently sets `aTokenAddress`; there is no partial-initialization state that later permits a second init. The claim does not match the code. |
| other | opencode_1 | Block Timestamp Dependency in Interest Accrual | Use of `block.timestamp` for accrual is standard and the report does not provide a concrete exploit beyond negligible validator timestamp freedom. |
| trust_or_owner_model | opencode_1 | No Access Control on rescueTokens Function | `rescueTokens` is explicitly restricted by `onlyPoolAdmin`. A compromised admin draining funds is a governance/key-management trust assumption, not a contract vulnerability. |
