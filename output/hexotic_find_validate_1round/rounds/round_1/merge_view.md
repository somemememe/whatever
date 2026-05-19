# Merge View - Round 1

## Summary
- total findings: 2
- new findings: 1
- updated existing findings: 1
- rejected candidates: 2

## Finding Actions
- existing_rewritten: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | existing_rewritten | High | high | codex | Order creation returns and emits `0` instead of the real live order ID | codex:0.204 Use of `transfer` for ETH payouts can permanently brick fills or refunds for contract-based users |
| F-002 | rewritten_agent_signal | Low | high | codex | ETH `transfer` makes some fills or cancellations fail for contract-based users | codex:0.606 Use of `transfer` for ETH payouts can permanently brick fills or refunds for contract-based users |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex | Live orders can become unmanageable and remain fillable because cancellation requires the undisclosed real order ID | Duplicate of F-001. The management/cancellation angle is the same root cause and is already covered in the existing finding's claim, impact, and attack paths. |
| other | codex | Verifier/helper swaps accept any output, exposing deposited ETH to sandwich extraction | The zero-slippage swaps are in `FlawVerifier.sol`/`VictimMaker`, which act as local exploit-verification helpers rather than the audited OTC market itself. This does not create protocol-level harm in `HEXOTC`, so it is out of scope as a reportable issue here. |
