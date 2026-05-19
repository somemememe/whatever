# Merge View - Round 4

## Summary
- total findings: 11
- new findings: 3
- updated existing findings: 0
- rejected candidates: 3

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 8
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-014 | rewritten_agent_signal | Low | medium | codex | Reward deposits are stranded when a pool keeps liquidity after total LP shares fall to zero | codex:0.568 Fee distributions are silently blackholed whenever a pool has liquidity recorded but zero LP shares |
| F-015 | exact_agent_candidate | Medium | medium | codex | Blocking a token also blocks the orderbook's repayment path, which can strand borrowed assets outside the pool | codex:1.0 Blocking a token also blocks the orderbook's repayment path, which can strand borrowed assets outside the pool |
| F-017 | rewritten_agent_signal | Medium | high | codex | Orderbook settlement cannot repay assets after draining a pool's tracked liquidity to zero | codex:0.434 Fee distributions are silently blackholed whenever a pool has liquidity recorded but zero LP shares |

## Rejection Reasons
- other: 1
- trust_or_owner_model: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | The designated orderbook can unilaterally drain pool inventory without any trade-level settlement checks | Rejected as a privileged-trust assumption: the registry-designated `orderbook` is explicitly granted raw custody powers, so a malicious or compromised orderbook draining funds is a centralization risk rather than a distinct pool-side vulnerability. |
| trust_or_owner_model | codex | Owner can bypass all LP accounting and seize every pooled asset through the emergency withdrawal backdoors | Rejected as an explicit admin backdoor: `onlyOwner` emergency sweep functions are intentional privileged powers, not an unintended exploit path available to untrusted actors. |
| other | codex | The advertised `minTokenAmount` slippage guard is non-functional | Rejected as non-material: the caller already specifies the exact `tokenAmount` to transfer and execution is bounded by the contract's fixed ratio check, so `minTokenAmount` being redundant/misdocumented is primarily a UX/API issue rather than a protocol-level vulnerability. |
