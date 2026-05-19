# Merge View - Round 3

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
| F-010 | exact_agent_candidate | Medium | high | codex | Existing pools can be bricked or mispriced because pair checks use the current router, not the stored pair | codex:1.0 Existing pools can be bricked or mispriced because pair checks use the current router, not the stored pair |
| F-011 | exact_agent_candidate | Medium | high | codex | Reward payouts are not isolated per pool, so one undercollateralized reward bucket can drain unrelated pools | codex:1.0 Reward payouts are not isolated per pool, so one undercollateralized reward bucket can drain unrelated pools |

## Rejection Reasons
- trust_or_owner_model: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Owner can unilaterally drain all LP principal and rewards | This is an explicit owner-only emergency sweep/backdoor and is best treated as a privileged trust assumption or centralization risk, not a distinct smart-contract vulnerability. |
| trust_or_owner_model | codex | Pool blindly trusts a mutable external registry for withdrawal authority | The pool is intentionally designed to trust an updatable registry for `orderbook` and reward-distributor authorization; exploiting this requires compromise or malicious control of a privileged dependency rather than a permissionless flaw in the pool itself. |
