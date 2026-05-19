# Merge View - Round 9

## Summary
- total findings: 20
- new findings: 3
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- existing_preserved: 17
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-029 | rewritten_agent_signal | Medium | high | codex | Convex pool configuration never validates that a `pid` matches the pair collateral | codex:0.613 Arbitrary Convex pool IDs can be activated without verifying they match the pair collateral |
| F-030 | rewritten_agent_signal | Medium | high | codex | Uncapped `minimumBorrowAmount` can make partial repayments and deleveraging impossible for existing borrowers | codex:0.715 Uncapped `minimumBorrowAmount` can turn repayments into all-or-nothing and trap existing borrowers |
| F-031 | rewritten_agent_signal | Low | high | codex | Zero `epochLength` in the core contract permanently bricks pair fee withdrawals | codex:0.803 Zero `epochLength` permanently bricks fee withdrawals |

## Rejection Reasons
- other: 1
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Redemption path releases collateral without any pair-side proof that debt tokens were paid or burned | `redeemCollateral()` is intentionally restricted to the registry-configured `redemptionHandler`; whether and how debt is burned is delegated to that trusted system component, so this depends on privileged-handler compromise or out-of-scope handler bugs rather than a pair-side invariant violation. |
| other | codex | Liquidation clears borrower debt before verifying the insurance-side burn actually happened | `liquidate()` is intentionally callable only by the registry-configured `liquidationHandler`, and the comment/documented flow explicitly delegates the burn to `processLiquidationDebt`; absent a bug in that trusted handler, this is an architectural trust assumption rather than a standalone pair vulnerability. |
