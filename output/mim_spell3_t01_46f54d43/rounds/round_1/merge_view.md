# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 2
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- existing_preserved: 3
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-102 | rewritten_agent_signal | High | high | codex | Residual debt cannot be forcibly liquidated after a position's collateral is exhausted | codex:0.59 Residual debt becomes permanently unliquidatable once a borrower runs out of collateral |
| F-103 | rewritten_agent_signal | High | medium | codex | Oracle precision mismatches can misprice collateral because `IOracle.decimals()` is ignored | codex:0.547 Oracle precision is hardcoded to 1e18 and ignores `IOracle.decimals()` |

## Rejection Reasons
- other: 1
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Privileged helper can mint arbitrary debt onto any user without transferring them MIM | Rejected as a reportable issue because the behavior is explicit, owner-gated functionality in `PrivilegedCauldronV4`; the root cause is trusted-admin misuse of a deliberately privileged variant rather than a permissionless or unintended flaw in the core cauldron logic. |
| other | codex | `repay(..., skim=true)` pulls from BentoBox's own balance instead of the expected skim source | The source does show an apparent skim/source mismatch, but the concrete exploitability depends on unseen BentoBox transfer-approval rules, and the practical impact is limited because borrowers still retain normal repayment paths. This is not strong enough as a protocol-level reportable finding from the in-scope code alone. |
