# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Flash-loan callback can reenter deposits and mint LP against temporarily drained balances | codex_1:0.72 Flash loan callback can mint massively underpriced LP shares against temporarily drained balances |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Factory-created curves hardwire swaps to a factory that lacks the required fee getter interface | codex_1:0.835 Factory-created curves hardwire swaps to a factory that does not implement the required fee getters |
| F-003 | rewritten_agent_signal | High | medium | codex_1,opencode_1 | Externally supplied assimilators execute via delegatecall and can seize pool state if malicious or upgradeable | codex_1:0.493 User actions delegatecall into externally supplied assimilators with full pool storage access |
| F-004 | exact_agent_candidate | Medium | high | codex_1 | Transferred LP tokens become non-withdrawable during the whitelist stage | codex_1:1.0 Transferred LP tokens become non-withdrawable during the whitelist stage |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 5
- trust_or_owner_model: 3
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Unlimited Token Approval to Untrusted Addresses | For factory-created pools the numeraire and reserve addresses are identical, so the `safeApprove` branch is not taken; the remaining concern is a deployment-time trust assumption rather than an exploitable bug in the shipped factory path. |
| trust_or_owner_model | opencode_1 | Owner Can Permanently Freeze Protocol Functions | This is an explicit privileged control, not a coding flaw; freezing blocks swaps but does not by itself create unintended fund loss, and proportional withdrawal remains available unless emergency mode is separately enabled. |
| other | opencode_1 | Whitelisted Depositors Can Withdraw More Than Deposited | The code does not enable double-withdrawal; after transferring LP away, the recipient is the one that gets stuck by whitelist underflow, while the original depositor still cannot burn more LP than they hold. |
| trust_or_owner_model | opencode_1 | Missing Parameter Validation Allows Dangerous Pool Configuration | `setParams` already enforces bounds on alpha, beta, fee-at-halt, epsilon, and lambda; the residual risk is ordinary owner/governance authority, not missing validation. |
| other | opencode_1 | Division by Zero When Pool Has Zero Total Supply | With zero total supply there is no outstanding LP-backed claim to redeem; this is only a zero-amount edge-case revert, not a realistic permanent lockup scenario. |
| trust_or_owner_model | opencode_1 | Flash Loan Fees Sent to Owner Instead of Protocol Treasury | This is an economic/design choice about fee recipient, not an unintended exploit path that lets an unprivileged attacker steal or lock protocol funds. |
| unsupported_or_speculative | opencode_1 | Oracle Price Manipulation Through External Dependencies | The report is generic and not supported by this codebase: `Storage.oracles` is declared but not wired into the pool pricing paths reviewed here. |
| other | opencode_1 | Hardcoded Merkle Root Cannot Be Updated | An immutable whitelist root is a design choice; by itself it does not create realistic theft, insolvency, or lockup beyond the intended whitelist policy. |
| other | opencode_1 | Deadline Check Uses Incorrect Comparison Operator | Using `<` instead of `<=` only affects transactions mined at the exact deadline timestamp and is a minor UX edge case, not a reportable security issue. |
| duplicate_or_subsumed | opencode_1 | CurveFactory Allows Creating Duplicate Pools with Same Currency Pair | The factory rejects duplicate ordered pairs and no deletion path is present; the claim about recreating deleted pools is unsupported by the code shown. |
