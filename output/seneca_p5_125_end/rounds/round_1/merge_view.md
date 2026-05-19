# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 15

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Unsupported batched operations clear the deferred solvency flag and enable undercollateralized borrows/withdrawals | codex_1:0.888 Unsupported operations clear the deferred solvency flag and enable uncollateralized borrows |
| F-002 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Oracle failures and zero exchange rates are accepted, allowing stale-price borrowing and zero-rate solvency bypasses | codex_1:0.529 Oracle failures fall back to stale or zero exchange rates, breaking solvency and liquidation |
| F-003 | exact_agent_candidate | Medium | high | codex_1 | Interest-rate changes are applied retroactively to already elapsed debt | codex_1:1.0 Interest-rate changes are applied retroactively to already elapsed debt |
| F-004 | rewritten_agent_signal | Medium | low | codex_1 | Any clone deployed without atomic initialization can be permanently captured because `init()` is unrestricted | codex_1:0.798 Any uninitialized clone can be permanently captured because `init()` is unrestricted |

## Rejection Reasons
- low_impact_or_operational: 2
- other: 12
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Missing array length validation in liquidate function | A shorter `maxBorrowParts` array only causes a bounds-check revert, and extra trailing entries are ignored; this does not liquidate the wrong user or create theft. |
| low_impact_or_operational | opencode_1 | Unlimited users can be liquidated in single transaction causing DoS | The caller chooses the array length and only risks its own transaction running out of gas; it does not block other liquidators from submitting smaller calls. |
| other | opencode_1 | No slippage protection in liquidation | The liquidator chooses whether to use a swapper and bears execution risk; if the required senUSD is not provided back, the final transfer reverts the whole transaction. |
| other | opencode_1 | Missing reentrancy guards on critical functions | No concrete reentrant exploit is supported by the cited code. The report is generic speculation about external calls. |
| other | opencode_1 | Oracle rate not validated in liquidation | Merged into F-002 as part of the broader stale/zero oracle-rate issue. |
| other | opencode_1 | Anyone can manipulate exchange rate via performOperations | `OPERATION_UPDATE_PRICE` only fetches the oracle's value; the caller cannot set an arbitrary exchange rate. |
| other | opencode_1 | Missing validation for zero exchange rate | Merged into F-002 as part of the broader zero/stale exchange-rate issue. |
| low_impact_or_operational | opencode_1 | Unbounded iteration in performOperations | This is caller-controlled gas consumption, not a protocol-level denial of service against other users. |
| other | opencode_1 | Oracle price can be zero in OPERATION_UPDATE_PRICE | Merged into F-002 as part of the broader zero/stale exchange-rate issue. |
| other | opencode_1 | Liquidator can be any address without access control | Permissionless liquidation is intentional protocol behavior, not a vulnerability. |
| other | opencode_1 | No minimum borrow amount check | Borrowing zero does not create realistic protocol harm beyond trivial dust state changes. |
| other | opencode_1 | Swapper not validated for malicious behavior | The liquidator supplies the swapper and the transaction reverts if repayment is not delivered; this is user-selected execution risk, not protocol theft. |
| other | opencode_1 | accruedInterest.lastAccrued can be zero initially | `init()` immediately calls `accumulate()`, which sets `lastAccrued` before any debt exists. |
| trust_or_owner_model | opencode_1 | No access control on changeInterestRate decrease | `changeInterestRate()` is already restricted to `onlyMasterContractOwner`; choosing a lower rate is governance policy, not missing access control. |
| other | opencode_1 | Blacklist can be bypassed in direct function calls | The blacklist is only used to restrict arbitrary external `OPERATION_CALL` targets; it is not intended as a global user access-control list. |
