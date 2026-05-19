# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Empty-vault inflation attack can steal later deposits via zero-share minting | codex_1:1.0 Empty-vault inflation attack can steal later deposits via zero-share minting |
| F-002 | rewritten_agent_signal | Medium | high | codex_1,opencode_1 | Permissionless repeated `earn()` calls can drain the withdrawal buffer to dust | codex_1:0.81 Permissionless repeated `earn()` calls can drain the vault's cash buffer to near zero |
| F-003 | exact_agent_candidate | Low | high | codex_1,opencode_1 | `getPricePerFullShare()` reverts while the vault is empty | codex_1:1.0 `getPricePerFullShare()` reverts while the vault is empty |

## Rejection Reasons
- duplicate_or_subsumed: 2
- factually_incorrect: 2
- other: 2
- trust_or_owner_model: 4

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Controller set to address(0) permanently locks all funds | Setting an invalid controller is a governance-only misconfiguration, and governance can later set a valid controller again; the claim of permanent lock is overstated and not a standalone protocol bug. |
| trust_or_owner_model | opencode_1 | Controller can drain any ERC20 tokens from vault via harvest() | `harvest()` is an explicitly privileged controller-only sweep for non-underlying tokens; this is a trust/roles assumption, not an unprivileged exploit. |
| other | opencode_1 | Division by zero in withdraw when totalSupply is zero | A meaningful withdraw cannot occur when `totalSupply()` is zero because no user holds shares then; this is only a trivial edge-case revert such as `withdraw(0)`. |
| factually_incorrect | opencode_1 | Division by zero in deposit when _pool is zero | The stated path is incorrect because if all users fully withdraw then `totalSupply()` also becomes zero, taking the first-deposit branch. The remaining `_pool == 0 && totalSupply() > 0` case requires prior total asset loss/insolvency, not a new logic flaw in `deposit()`. |
| trust_or_owner_model | opencode_1 | setMin can be set to 0, disabling yield generation | This is a governance-controlled configuration choice rather than an exploitable vulnerability. |
| duplicate_or_subsumed | opencode_1 | No slippage protection allows sandwich attacks on deposit/withdraw | The claim is too generic for this share vault design and does not show a concrete profitable manipulation beyond the separate donation/inflation issue already captured. |
| other | opencode_1 | No deadline parameter allows unfavorable transaction execution | This is a generic UX/property complaint, not a concrete protocol vulnerability in the vault logic. |
| trust_or_owner_model | opencode_1 | setController has no validation allowing malicious controller | Choosing the controller is a governance trust boundary; governance can already point the vault at any controller, so this does not introduce an additional permissionless exploit. |
| duplicate_or_subsumed | opencode_1 | earn() can be called by anyone triggering unnecessary operations | Subsumed by the stronger finding that repeated public `earn()` calls can drain the local withdrawal buffer to dust. |
| factually_incorrect | opencode_1 | Missing ERC20 transfer return value check in deposit (indirect) | Incorrect: `deposit()` uses `SafeERC20.safeTransferFrom`, which already checks call success and optional return values. |
