# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Unlimited gateway approvals persist and survive router delisting, enabling drains of proxy-held tokens | codex_1:0.684 Unlimited gateway approvals persist and can drain proxy-held tokens even after delisting |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Fee-on-transfer tokens are accounted by nominal input instead of actual receipt, allowing reserve drain | codex_1:0.612 Fee-on-transfer tokens can drain accumulated reserves because spending is based on nominal input, not actual receipt |
| F-003 | rewritten_agent_signal | Low | high | codex_1 | Configured per-token minimum and maximum route amounts are never enforced | codex_1:0.651 Configured per-token min/max amount limits are dead code |
| F-004 | rewritten_agent_signal | Medium | medium | codex_1 | Caller-controlled integrator address lets anyone impersonate discounted fee plans | codex_1:0.667 Unauthenticated integrator field lets anyone reuse discounted fee schedules |

## Rejection Reasons
- duplicate_or_subsumed: 2
- other: 6

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | opencode_1 | SmartApprove grants unlimited approvals to potentially malicious gateways | Subsumed by F-001. The reportable issue is the persistent overbroad approval that remains live after use and after delisting, not a separate standalone bug. |
| duplicate_or_subsumed | opencode_1 | No approval cleanup on router/gateway removal | Subsumed by F-001 as part of the same sticky-approval root cause. |
| other | opencode_1 | Flash loan attack vector via Uniswap V2 | The cited `FlawVerifier` is a local verification harness, not production protocol code. Flash liquidity is only part of an exploit path for other bugs, not a standalone vulnerability here. |
| other | opencode_1 | No event emission for ERC20 approvals | ERC20 approval state is already observable from token contracts; absence of an extra wrapper event is not a protocol vulnerability. |
| other | opencode_1 | sweepTokens allows admin to drain all tokens | This is an explicit admin power/centralization property, not an unintended vulnerability in the protocol logic. |
| other | opencode_1 | Missing zero-address validation in sweepTokens | `sweepTokens` is admin-only and delegates to `sendToken`; this does not create a realistic permissionless exploit or protocol-level harm. |
| other | opencode_1 | Fixed crypto fee underflow protection comment is misleading | This is documentation quality, not a security issue. |
| other | codex_1 | Native routing emits unvalidated amount metadata | The mismatch only affects off-chain interpretation of caller-supplied event fields; no concrete on-chain fund loss or permissionless protocol exploit is evidenced in the code. |
