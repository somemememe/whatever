# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex | Depositing while assets are parked in the orderbook mints inflated LP shares | codex:0.764 Depositing while the orderbook holds assets mints inflated LP shares |
| F-002 | exact_agent_candidate | High | high | codex | Reward accounting mixes raw deposits and LP shares, enabling reward theft and withdrawal lockups | codex:0.939 Reward accounting mixes raw deposits and LP shares, enabling reward theft and lockups |
| F-003 | rewritten_agent_signal | High | medium | codex | Nominal token amounts are credited even when fewer tokens are actually received | codex:0.425 The `minTokenAmount` parameter provides no real slippage protection |
| F-006 | rewritten_agent_signal | High | high | merge-review | A full orderbook drain bricks the pool because returned assets are rejected when liquidity reaches zero | codex:0.398 Depositing while the orderbook holds assets mints inflated LP shares |

## Rejection Reasons
- other: 1
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Owner can unconditionally drain all pool and reward assets | This is an explicit `onlyOwner` emergency escape hatch documented in the contract comments. Without evidence that privileged emergency powers are out of scope or hidden from users, this is a trust-model/centralization concern rather than a distinct code vulnerability. |
| other | codex | The `minTokenAmount` parameter provides no real slippage protection | `minTokenAmount` is redundant, but the function still enforces the live reserve ratio within a hard ±1% band. The issue does not create a concrete exploit or meaningful additional user harm beyond a misleading parameter name. |
