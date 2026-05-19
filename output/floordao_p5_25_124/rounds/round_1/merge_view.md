# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Warmup deposits are rebased but never counted as liabilities, allowing staking insolvency | codex_1:0.927 Warmup deposits are rebased but never counted as liabilities, allowing protocol insolvency |
| F-002 | rewritten_agent_signal | Medium | low | codex_1 | Rebase accounting relies on external `circulatingSupply()` semantics to include wrapped gFLOOR liabilities | codex_1:0.317 Authorized third parties can force a matured warmup claim into the wrong asset form |
| F-003 | rewritten_agent_signal | High | high | codex_1,opencode_1 | An opted-in warmup position can be locked indefinitely because every added stake resets the entire expiry | codex_1:0.468 A dust deposit can indefinitely reset another user's warmup timer and lock their entire position |

## Rejection Reasons
- factually_incorrect: 3
- other: 6
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | The lock flag is implemented with inverted semantics relative to its protection comment | Merged into F-003 because the misleading `toggleLock()` semantics materially increase exposure to the timer-reset lockup, but the comment inversion alone is not the main protocol harm. |
| other | codex_1 | Authorized third parties can force a matured warmup claim into the wrong asset form | Does not create direct fund loss, insolvency, or lockup; it is primarily a preference and integration-friction issue. |
| other | codex_1 | secondsToNextEpoch reverts exactly when the protocol most needs it | Informational helper behavior only; not a reportable security issue. |
| other | opencode_1 | Forfeit function loses rebased tokens during warmup | Matches the contract's explicit early-exit semantics: forfeiting returns principal while abandoning warmup rewards. That is a design choice, not an unintended vulnerability. |
| factually_incorrect | opencode_1 | setWarmupLength retroactively modifies all existing warmup periods | Incorrect. Existing claims use the stored per-position `expiry`, and `claim()` does not reference the current `warmupPeriod`. |
| factually_incorrect | opencode_1 | Unstake lacks slippage protection against rebase volatility | Incorrect framing. `unstake()` redeems a deterministic token amount, not a slippage-prone trade, and no negative-rebase mechanism is shown in scope. |
| trust_or_owner_model | opencode_1 | Insufficient FLOOR balance can cause permanent unstake DoS | This is a consequence of insolvency or out-of-scope privileged abuse, not an independent flaw in `unstake()`. The in-scope accounting root cause is captured in F-001. |
| other | opencode_1 | Missing zero-amount validation in stake function | Merged into F-003 because the missing check matters insofar as it makes the warmup timer-reset attack nearly free. |
| factually_incorrect | opencode_1 | toggleLock can be used to grief own warmup position | Incorrect characterization. The meaningful issue is third-party access plus expiry reset, which is captured in F-003. |
| other | opencode_1 | wrap and unwrap lack allowance validation | Standard ERC20 allowance failures already revert; this is a UX concern, not a security finding. |
