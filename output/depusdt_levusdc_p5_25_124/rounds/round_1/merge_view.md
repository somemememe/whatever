# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 9

## Finding Actions
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | Public arbitrary-token approval lets any caller steal the market's USDT, cUSDT, and other ERC-20 balances | codex_1:0.847 Public arbitrary-token approval lets any caller drain the market's USDT and cToken balances |
| F-002 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Redeem burns full DepTokens even when Compound withdrawal fails and only partial cash is available | codex_1:0.794 Redeem burns full DepTokens even when external liquidity retrieval fails and only a partial payout is available |
| F-003 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Curve swaps use zero minimum output, enabling sandwich extraction on borrow and refund flows | codex_1:0.653 All Curve swaps execute with zero slippage protection, enabling sandwich extraction and value loss |
| F-004 | rewritten_agent_signal | Medium | medium | codex_1 | Ignored Compound mint errors can brick later USDT resupply attempts via stale allowance | codex_1:0.595 Ignored Compound mint errors can leave a stuck non-zero allowance and permanently DoS future supply attempts |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 6
- trust_or_owner_model: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Missing nonReentrant guard on updateBorrowLedger allows reentrancy attack | Rejected. `updateBorrowLedger` is internal-only, and every reachable caller in this codebase (`redeemInternal` and `repayBorrowInternal`) already runs under the contract-level `nonReentrant` guard. |
| trust_or_owner_model | opencode_1 | Admin can set malicious Compound and Curve addresses to steal user funds | Rejected. This is an admin-trust/governance-risk observation, not a standalone code vulnerability under the stated reporting standard. |
| other | opencode_1 | No minimum amount validation on Compound withdrawals | Rejected as a standalone item. The reportable issue is the specific redeem path that ignores Compound withdrawal failure and still burns full shares; the generic 'no minimum' framing is too broad. |
| other | opencode_1 | No validation of external protocol return values | Rejected as a standalone item. The claim is overbroad; most of the cited calls are not independently exploitable, while the materially harmful unchecked-return cases are captured in the specific findings above. |
| other | opencode_1 | Unchecked return value from SafeERC20.approve | Rejected. `safeApprove` does not return an unchecked boolean here; it reverts on low-level failure or on a decoded `false` return. |
| trust_or_owner_model | opencode_1 | No two-step admin transfer or timelock on critical functions | Rejected. Lack of timelock is governance hardening, not a concrete protocol vulnerability in this threat model; admin transfer itself already uses a pending-admin acceptance flow. |
| other | opencode_1 | Division precision loss in interest calculations | Rejected. Integer truncation is expected in fixed-point accounting and no concrete exploit path or material protocol harm was demonstrated. |
| duplicate_or_subsumed | opencode_1 | Redemption can return less than requested without user notification | Rejected as a standalone item because the material issue is stronger and already captured: the contract can burn the full share amount while paying only the reduced cash amount. |
| other | opencode_1 | Exchange rate calculation excludes reserves in certain conditions | Rejected. The cited implementation already subtracts reserves via `getCashExReserves()` before computing `(cash + borrows) / totalSupply`; the candidate does not show a real edge-case bug. |
