# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 16

## Finding Actions
- exact_agent_candidate: 3
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | medium | codex_1 | Flashloan debt opening reuses a stale eMode snapshot after callback state changes | codex_1:0.929 Flashloan debt opening uses a stale eMode snapshot after arbitrary callback state changes |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Isolation debt ceilings can be bypassed with repeated sub-unit borrows | codex_1:0.623 Isolation debt ceilings can be bypassed by splitting borrows below the 0.01-token accounting unit |
| F-003 | exact_agent_candidate | Medium | high | codex_1 | Reserve deletion ignores outstanding unbacked bridge liabilities | codex_1:1.0 Reserve deletion ignores outstanding unbacked bridge liabilities |
| F-005 | rewritten_agent_signal | Medium | high | codex_1 | feeToVault is never actually paid despite vault-fee accounting and events | codex_1:0.814 feeToVault is never actually paid despite emitting vault fee events |
| F-006 | exact_agent_candidate | Low | high | codex_1 | Invalid flashloan premium splits can brick flashloan repayment | codex_1:0.896 Unchecked flashloan premium split can brick flashloan repayment |

## Rejection Reasons
- other: 12
- trust_or_owner_model: 4

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Any account can frontrun proxy initialization | This is a generic deployment-time race on an uninitialized proxy, not a demonstrated runtime protocol bug in the reviewed codebase; no non-atomic deployment flow was evidenced. |
| other | opencode_1 | No Access Control on rescueTokens Function | False positive. `Pool.rescueTokens` is protected by `onlyPoolAdmin` before it reaches `PoolLogic.executeRescueTokens`. |
| trust_or_owner_model | opencode_1 | Unchecked Liquidation Bonus Allows Protocol Loss | This depends on privileged governance writing nonsensical reserve parameters; no permissionless exploit path was shown. |
| other | opencode_1 | No Health Factor Validation When Switching eMode from Category 0 | The issue is user-self-inflicted and does not by itself create a protocol-level exploit or bad-debt primitive. |
| other | opencode_1 | Oracle Price Manipulation Risk | Generic oracle-trust concern only. The reviewed code does not show that the configured oracle source is manipulable or attacker-controlled. |
| other | opencode_1 | feeToVault Can Be Set to Zero Address | Not a distinct vulnerability here. The retained vault-fee finding already shows that the vault is never paid at all, regardless of recipient address. |
| other | opencode_1 | No Slippage Protection in Withdraw | Withdrawals are deterministic lending redemptions, not market-priced swaps, so swap-style slippage protection is not applicable. |
| other | opencode_1 | Unbacked Minting Without Health Factor Check | `mintUnbacked` is restricted to the trusted bridge role, and the resulting exposure is explicitly tracked via `reserve.unbacked`; this is not a permissionless exploit. |
| trust_or_owner_model | opencode_1 | FlashLoan Premium Can Be Set to 100% | High premiums alone are a governance choice, not a vulnerability. The retained flashloan finding covers the concrete missing split invariant that can break repayment. |
| other | opencode_1 | Rebalance Stable Rate Does Not Validate New Rate | Stable-rate rebalancing is intended protocol behavior and is gated by `ValidationLogic.validateRebalanceStableBorrowRate`. |
| other | opencode_1 | setLendingGauge Allows Zero Address Without Validation | A zero gauge is handled by the surrounding code paths and merely disables reward-allocation updates; no security impact was shown. |
| trust_or_owner_model | opencode_1 | Missing Validation for Liquidation Bonus vs LTV Relationship | This is another privileged configuration-hygiene concern without a concrete exploit path beyond governance setting arbitrary bad parameters. |
| other | opencode_1 | Division by Zero in Health Factor Calculation | False positive. The zero-collateral case is explicitly handled, and the shown code path does not divide by zero. |
| other | opencode_1 | No Access Control on initialize Function After First Initialization | False positive. `initializer` prevents repeated calls, and front-running `Pool.initialize` does not seize privileges or change the immutable provider. |
| other | opencode_1 | Integer Overflow in Isolation Mode Debt Calculation | False positive. Solidity 0.8 checked arithmetic plus `SafeCast` and bounded debt-ceiling storage prevent silent truncation/overflow here. |
| trust_or_owner_model | opencode_1 | Missing Validation for Debt Ceiling in Isolation Mode | A large debt ceiling chosen by governance is a risk-parameter decision, not a code vulnerability by itself. |
