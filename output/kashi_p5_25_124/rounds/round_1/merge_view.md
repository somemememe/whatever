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
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | Freshly initialized markets are immediately borrowable at a zero exchange rate | codex_1:0.646 Freshly initialized markets can be drained because `exchangeRate` starts at zero |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Solvency-critical actions trust arbitrarily stale cached oracle prices | codex_1:0.57 Borrowing, collateral removal, and liquidation all rely on arbitrarily stale cached oracle data |
| F-003 | rewritten_agent_signal | Medium | high | codex_1 | `cook()` max-rate protection is inverted and only passes above the caller's ceiling | codex_1:0.5 The `cook` exchange-rate upper bound is inverted, so slippage protection only passes at worse-than-allowed prices |
| F-004 | rewritten_agent_signal | Medium | high | codex_1,opencode_1 | Permissionless `cook()` calls can sweep stray ETH and directly transferred tokens from the Cauldron | codex_1:0.426 Anyone can steal ETH or tokens stranded on the Cauldron through unrestricted `cook` calls |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 6
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Missing access control on init function allows setting malicious oracle | `init()` is the intended clone initializer invoked during `BentoBox.deploy`; no concrete path was shown to hijack already deployed funded markets, and initializing the master contract itself does not compromise existing clones. |
| other | opencode_1 | Reentrancy vulnerability in liquidate function via arbitrary swapper | The swapper callback occurs before the final MIM repayment transfer, and any failure to repay reverts the entire liquidation; no concrete reentrant path to steal collateral or corrupt accounting was validated. |
| other | opencode_1 | No slippage protection in liquidation swap | Open liquidation intentionally lets the caller choose `to` and `swapper`; the liquidator bears that execution risk, so this is not a protocol vulnerability. |
| duplicate_or_subsumed | opencode_1 | Oracle price not validated for reasonableness | This is a generic oracle-trust observation rather than a distinct code flaw; the concrete reportable oracle issues here are the stale/zero cached-rate behaviors already captured separately. |
| other | opencode_1 | Open liquidation allows front-running and MEV extraction | Permissionless liquidation and MEV competition are expected market mechanics, not a code-level vulnerability. |
| other | opencode_1 | Potential integer overflow in accrue interest calculation | The arithmetic is checked, and the described overflow requires extreme/unrealistic values or time horizons, making it non-practical as a protocol risk. |
| other | opencode_1 | Missing event for critical reduceSupply function | Informational only; it does not create realistic protocol-level harm. |
| trust_or_owner_model | opencode_1 | No access control on setFeeTo function | `setFeeTo()` is protected by `onlyOwner`; setting a poor recipient is an authorized governance choice, not missing access control. |
