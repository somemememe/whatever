# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 6

## Finding Actions
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Emergency exits permanently invalidate LinearPool virtual-supply accounting, yet the pool auto-resumes normal operation after the buffer period | codex_1:0.409 Emergency exits can leave the pool in an invalid state that automatically becomes live again |
| F-002 | rewritten_agent_signal | Medium | low | codex_1 | `getRate()` can expose transient join/exit state as a manipulable on-chain rate oracle | codex_1:0.793 Unprotected `getRate()` can observe transient join/exit state and act as a manipulable rate oracle |
| F-003 | rewritten_agent_signal | Medium | low | codex_1,opencode_1 | AaveLinearPool does not enforce that the wrapped token actually matches the Aave rate source it uses for pricing | codex_1:0.414 AaveLinearPool over-trusts wrapper metadata and can overvalue an incompatible wrapped token |

## Rejection Reasons
- other: 5
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Wrapped Token Rate Oracle Manipulation | `getReserveNormalizedIncome` is an Aave accrual index, not a spot price that an attacker can realistically pump and revert with a simple same-block deposit/withdraw arbitrage as described. |
| other | opencode_1 | Owner Can Exploit Pending Fees via setTargets | `setTargets` already requires the current main balance to be within both the current targets and the proposed new targets, which prevents changing target ranges while fees are pending. |
| other | opencode_1 | Initialization Front-Running Vulnerability | `initialize()` is intentionally public and only performs the one-time self-join that mints preminted BPT to the pool itself; the report does not show theft, lockup, or other protocol-level harm from a third party calling it first. |
| other | opencode_1 | Potential Division by Zero in LinearMath._fromNominal | `BasePool` caps `swapFeePercentage` at 10%, so `FixedPoint.ONE - fee` cannot approach zero in a way that causes the claimed failure mode. |
| other | opencode_1 | Query Functions Allow Arbitrary Caller | `queryJoin` and `queryExit` are intentionally external non-view quote helpers that use a revert-based self-call pattern; they do not commit state and the report does not establish a concrete harmful side effect. |
| trust_or_owner_model | opencode_1 | Missing Access Control on setSwapFeePercentage | Access control is not missing: `setSwapFeePercentage` is protected by `authenticate` through the Vault Authorizer by design. A compromised admin is a governance threat model, not a contract bug here. |
