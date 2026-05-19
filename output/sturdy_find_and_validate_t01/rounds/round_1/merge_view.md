# Merge View - Round 1

## Summary
- total findings: 2
- new findings: 1
- updated existing findings: 1
- rejected candidates: 4

## Finding Actions
- existing_rewritten: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | existing_rewritten | Critical | high | codex | Transient Balancer `exitPool` state can inflate Balancer-LP collateral prices and bypass collateral-removal solvency checks | codex:0.489 Transient Balancer-exit pricing window likely also enables over-borrowing, not only collateral removal |
| F-002 | rewritten_agent_signal | High | low | codex | The same transient Balancer-exit pricing window likely also permits direct over-borrowing during the callback | codex:0.72 Transient Balancer-exit pricing window likely also enables over-borrowing, not only collateral removal |

## Rejection Reasons
- low_impact_or_operational: 1
- other: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | codex | Debtors can self-liquidate and internalize the liquidation bonus | The code only shows self-liquidation being used after the primary oracle-manipulation exploit has already made the position unhealthy; it is not shown to create independent protocol loss, and on its own it mostly changes who captures the liquidation bonus rather than harming the pool. |
| other | codex | ERC20 helper libraries accept EOAs and non-contract addresses as successful token operations | This is a generic helper-library caveat, but the in-scope code does not show any protocol flow where token addresses are user-controlled or misconfigured, so no concrete exploitable path is established here. |
| other | codex | safeApprove wrappers preserve the ERC20 allowance race condition | This is the standard ERC20 approval caveat in generic helper code; no in-scope protocol flow demonstrates a non-zero-to-non-zero allowance change to an adversarial spender that would make it a distinct reportable issue. |
| low_impact_or_operational | codex | ETH helper functions forward all gas and turn payouts into reentrancy gadgets | Forwarding gas during ETH sends is only a reentrancy primitive, not a vulnerability by itself, and the provided code does not show an unsafe state-changing caller using these helpers in a way that creates a separate exploitable bug. |
