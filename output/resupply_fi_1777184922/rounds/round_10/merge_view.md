# Merge View - Round 10

## Summary
- total findings: 21
- new findings: 1
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 20

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-032 | exact_agent_candidate | High | medium | codex | Swapper-assisted price moves bypass the final solvency check | codex:1.0 Swapper-assisted price moves bypass the final solvency check |

## Rejection Reasons
- trust_or_owner_model: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Unbounded caller-supplied redemption fee can brick all redemptions | `redeemCollateral()` is callable only by the registry's privileged `redemptionHandler`; supplying an out-of-range `_totalFeePct` just makes that handler's own call revert and is better treated as an upstream handler bug/misconfiguration than a distinct pair vulnerability. |
| unsupported_or_speculative | codex | Leftover debt-token refunds ignore ERC20 transfer failures | The raw `transfer` is stylistically weaker than `safeTransfer`, but realistic harm depends on the protocol-controlled debt token being a nonstandard false-returning ERC20 despite the codebase otherwise assuming a standard mint/burn token; that scenario is too speculative for a reportable issue here. |
