# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 0

## Finding Actions
- rewritten_agent_signal: 5

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | Public `calcStepIncome` lets any player mint arbitrary withdrawable rewards | codex_1:0.355 Re-entering users can reactivate arbitrary inactive accounts and restore their old reward caps |
| F-002 | rewritten_agent_signal | High | high | codex_1 | The final-withdraw branch zeroes the round balance before paying, permanently orphaning current-round claims | codex_1:0.72 The final-withdrawal branch zeroes the pool before transferring, permanently trapping the remaining ETH |
| F-003 | rewritten_agent_signal | High | high | codex_1 | Any joiner can reactivate arbitrary dormant accounts and restore their old earning rights | codex_1:0.765 Re-entering users can reactivate arbitrary inactive accounts and restore their old reward caps |
| F-004 | rewritten_agent_signal | High | medium | codex_1 | Hardcoded VIP addresses receive a built-in 20,000x reward-cap backdoor | codex_1:0.766 Hardcoded VIP EOAs have a built-in 20,000x payout backdoor |
| F-005 | rewritten_agent_signal | Medium | high | codex_1 | The last insurance claimant can lose the entire residual payout because the pool is zeroed before the assignment | codex_1:0.804 The last insurance claimant can lose the entire residual payout due to assignment order |

## Rejection Reasons
- none
