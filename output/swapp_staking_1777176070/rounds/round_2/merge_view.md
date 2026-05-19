# Merge View - Round 2

## Summary
- total findings: 8
- new findings: 2
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- exact_agent_candidate: 2
- existing_preserved: 6

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-008 | exact_agent_candidate | Medium | high | codex,merge-review | Direct token transfers or rebases permanently poison non-stable pool-size accounting | codex:1.0 Direct token transfers or rebases permanently poison non-stable pool-size accounting |
| F-009 | exact_agent_candidate | Low | medium | codex,merge-review | Uninitialized historical epochs read mutable current balances instead of fixed snapshots | codex:1.0 Uninitialized historical epochs read mutable current balances instead of fixed snapshots |

## Rejection Reasons
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | codex | Anyone can reset epoch 0 to zero and corrupt the first live epoch’s denominator | Unsupported as a reportable issue: any epoch-0 `deposit()` already initializes `poolSize[token][1]` from the live balance, so later resetting epoch 0 does not retroactively zero the first rewarded epoch. Epoch 0 itself is explicitly a bootstrap epoch with no rewards. |
| unsupported_or_speculative | codex | Bootstrap deposits more than one epoch early receive multipliers above 100% | The >100% multiplier only affects epoch-0 effective-balance math. `deposit()` sets epoch 1 pool size from the raw token balance, not from the multiplied checkpoint value, so the claimed propagation into the first live epoch is not supported by the code. |
