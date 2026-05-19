# Merge View - Round 3

## Summary
- total findings: 7
- new findings: 3
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- exact_agent_candidate: 2
- existing_preserved: 4
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-005 | exact_agent_candidate | High | medium | codex | Unconditional reward claiming can globally freeze borrowing, repayments, withdrawals, and liquidations | codex:0.882 Unconditional reward claiming can globally freeze borrowing, withdrawals, repayments, and liquidations |
| F-007 | exact_agent_candidate | High | medium | codex | Zero oracle prices cause division-by-zero reverts across critical pair flows | codex:1.0 Zero oracle prices cause division-by-zero reverts across critical pair flows |
| F-009 | rewritten_agent_signal | Low | medium | codex | Share-refactor floor rounding can leak small amounts of debt and leave unowned borrow shares | codex:0.686 Share-refactor floor rounding leaks small amounts of debt during epoch migration |

## Rejection Reasons
- other: 1
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Interest accrual silently forgives entire periods once `uint128` debt headroom is exhausted | `borrowLimit` is explicitly capped to `type(uint128).max`, so reaching the overflow branch requires debt to already sit near the 128-bit ceiling (roughly 3e20 whole 18-decimal tokens). That is an extreme parameter/economic regime rather than a realistic standalone protocol failure mode here. |
| trust_or_owner_model | codex | Redemption and liquidation trust external handlers to burn debt but never verify it on-chain | These entrypoints are intentionally restricted to registry-designated `redemptionHandler` and `liquidationHandler` contracts, and the code/comments explicitly delegate the burn step to those trusted modules. A compromised or buggy privileged handler is a governance/trust failure, not a distinct pair-level vulnerability. |
