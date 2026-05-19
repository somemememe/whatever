# Merge View - Round 1

## Summary
- total findings: 2
- new findings: 2
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | medium | codex | Unprotected V3 reinitializer lets any caller seize the `rtusd0` dependency | codex:1.0 Unprotected V3 reinitializer lets any caller seize the `rtusd0` dependency |
| F-002 | rewritten_agent_signal | High | high | codex | `bUSD0` holders can redeem backing without burning the paired `rtUSD0` | codex:0.632 bUSD0 holders can unilaterally consume collateral without burning matching rt-USD0 |

## Rejection Reasons
- other: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | The 'burn USUAL' early-unlock path does not burn USUAL at all | The code clearly transfers USUAL into `accumulatedFees` and later forwards it to the distribution module, but the support for this being a reportable vulnerability is weak: the evidence is mainly stale comments/event naming, and no concrete exploit or protocol-state break is shown beyond a documentation/economic-design mismatch. |
| other | codex | Minting is allowed before `bondStart` even though `bondStart` is documented as the mint gate | The code does allow minting before `bondStart`, but the only support that this is unintended is an interface comment on `getStartTime()`. There is not enough evidence that pre-start minting violates an enforced invariant or creates realistic protocol-level harm rather than reflecting a deliberate pre-start deposit design. |
