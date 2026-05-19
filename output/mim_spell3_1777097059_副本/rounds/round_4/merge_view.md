# Merge View - Round 4

## Summary
- total findings: 14
- new findings: 4
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- exact_agent_candidate: 3
- existing_preserved: 10
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-012 | exact_agent_candidate | Medium | high | codex | Unbounded collateralization-rate updates can turn the market into free-borrow or mass-liquidation mode | codex:1.0 Unbounded collateralization-rate updates can turn the market into free-borrow or mass-liquidation mode |
| F-013 | exact_agent_candidate | Medium | high | codex | Missing interest-rate cap lets a single update brick `accrue()` and freeze core operations | codex:1.0 Missing interest-rate cap lets a single update brick `accrue()` and freeze core operations |
| F-014 | exact_agent_candidate | Medium | high | codex | `reduceSupply()` can withdraw MIM that `withdrawFees()` still counts as earned protocol fees | codex:1.0 `reduceSupply()` can withdraw MIM that `withdrawFees()` still counts as earned protocol fees |
| F-017 | rewritten_agent_signal | Medium | high | codex | Unbounded liquidation-multiplier updates can brick liquidations or over-seize collateral | codex:0.526 Unbounded collateralization-rate updates can turn the market into free-borrow or mass-liquidation mode |

## Rejection Reasons
- other: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Public `init()` allows hostile first-initialization of any orphaned clone | `init()` is public on clones, but the repo shows no in-protocol deployment path that leaves a legitimate clone uninitialized; BentoBox-style master-contract deployments normally initialize atomically. This is too contingent on an external deployment mistake to treat as a reportable protocol issue here. |
| other | codex | Batch liquidation rounds down each account's debt separately and can strand residual bad debt | The rounding loss is bounded to less than one smallest debt unit per liquidated account, making the aggregate effect dust-only and not a realistic protocol-level harm. |
