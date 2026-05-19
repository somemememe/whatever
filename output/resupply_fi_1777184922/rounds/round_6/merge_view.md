# Merge View - Round 6

## Summary
- total findings: 12
- new findings: 1
- updated existing findings: 0
- rejected candidates: 3

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 11

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-019 | exact_agent_candidate | Medium | high | codex | Any registered reward token that misbehaves can freeze borrower-facing pair operations | codex:1.0 Any registered reward token that misbehaves can freeze borrower-facing pair operations |

## Rejection Reasons
- other: 1
- trust_or_owner_model: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Redemption settlement is never verified before collateral leaves the pair | `redeemCollateral()` is explicitly restricted to the registry-selected `redemptionHandler`; the pair intentionally delegates redemption settlement to that privileged module, so this is a trusted-integration assumption rather than an independent code flaw in the pair. |
| trust_or_owner_model | codex | Liquidation handler can zero borrower debt before any repayment is proven | The code deliberately relies on the privileged `liquidationHandler` to burn debt from the insurance pool after `_repay(..., address(0), ...)`; absent a bug in that trusted handler implementation, this is architectural trust rather than a standalone pair vulnerability. |
| other | codex | Critical solvency and redemption math trusts a raw synchronous oracle value with no freshness or sanity bounds | This is a generic oracle-quality critique without a concrete manipulable or stale oracle implementation in scope. The source shows no timestamp/deviation interface to enforce, so exploitability depends on external oracle design/configuration rather than a demonstrable bug here. |
