# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- exact_agent_candidate: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex | Unlimited gateway approvals persist indefinitely and let any compromised allowlisted spender drain proxy-held ERC20 balances | codex:0.888 Unlimited gateway approvals let any compromised allowlisted spender drain proxy-held ERC20 balances |
| F-002 | exact_agent_candidate | Medium | high | codex | Gateway approval is not bound to the executed router, so callers can arm unrelated allowlisted spenders | codex:1.0 Gateway approval is not bound to the executed router, so callers can arm unrelated allowlisted spenders |
| F-003 | exact_agent_candidate | Low | high | codex | Configured per-token min/max limits are dead code and never enforced on bridge entrypoints | codex:1.0 Configured per-token min/max limits are dead code and never enforced on bridge entrypoints |

## Rejection Reasons
- other: 1
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex | Admin role can be permanently burned by transferring it to the zero address | This is a privileged self-misconfiguration by an existing admin, not an unprivileged exploit path; any resulting loss of control depends on operator error rather than a protocol vulnerability. |
| other | codex | Core route metadata is only emitted in events and is not enforced against calldata | This is mainly an off-chain event-integrity issue. The contract still executes only the router calldata, so the mismatch does not by itself enable on-chain fund theft, protocol insolvency, or permissionless DoS. |
