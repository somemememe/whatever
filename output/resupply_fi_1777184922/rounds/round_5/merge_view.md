# Merge View - Round 5

## Summary
- total findings: 11
- new findings: 2
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- exact_agent_candidate: 2
- existing_preserved: 9

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-013 | exact_agent_candidate | Medium | high | codex | Reward-manager invalidation can disable the internal write-off token and break redemption accounting | codex:1.0 Reward-manager invalidation can disable the internal write-off token and break redemption accounting |
| F-016 | exact_agent_candidate | High | high | codex | Constructor bypasses the max-LTV safety cap enforced by the runtime setter | codex:1.0 Constructor bypasses the max-LTV safety cap enforced by the runtime setter |

## Rejection Reasons
- trust_or_owner_model: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Redemptions release collateral without proving the stablecoins were actually burned | `redeemCollateral()` is intentionally restricted to the registry's trusted `redemptionHandler`, and the burn/settlement step is delegated to that privileged protocol component. A buggy or malicious handler is a trusted-component failure, not a pair-level vulnerability. |
| trust_or_owner_model | codex | Liquidations erase borrower debt before confirming the handler paid or burned it | `liquidate()` is callable only by the registry's trusted `liquidationHandler`, and the design explicitly delegates debt settlement to `processLiquidationDebt()`. Underpayment by that privileged handler is a trust-boundary failure rather than a missing permissionless invariant in the pair itself. |
