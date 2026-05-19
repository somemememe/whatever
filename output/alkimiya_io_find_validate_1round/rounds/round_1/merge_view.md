# Merge View - Round 1

## Summary
- total findings: 6
- new findings: 6
- updated existing findings: 0
- rejected candidates: 0

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 5

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex | Signed orders can be replayed and overfilled indefinitely | codex:1.0 Signed orders can be replayed and overfilled indefinitely |
| F-002 | rewritten_agent_signal | High | high | codex | Settlement can be manipulated by delaying start and end snapshots away from the target window | codex:0.811 Anyone can manipulate settlement by delaying start/end snapshots away from the target window |
| F-003 | rewritten_agent_signal | High | high | codex | Pools on decreasing indices can become permanently unendable | codex:0.829 Pools on non-monotonic indices can become permanently unendable |
| F-004 | rewritten_agent_signal | Medium | medium | codex | Deflationary or negative-rebasing payout tokens can undercollateralize pools | codex:0.58 Fee-on-transfer or rebasing payout tokens make pools insolvent |
| F-005 | rewritten_agent_signal | Medium | medium | codex | Orders remain fillable after pool start or even after maturity until explicit finalization | codex:0.356 Fresh exposure can still be minted after the market outcome is partly or fully known |
| F-006 | rewritten_agent_signal | Medium | high | codex | Emergency pause only blocks order filling, not direct minting or pool lifecycle actions | codex:0.551 Emergency pause does not stop direct minting, settlement, refunds, or redemption |

## Rejection Reasons
- none
