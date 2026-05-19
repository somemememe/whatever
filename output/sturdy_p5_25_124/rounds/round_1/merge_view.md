# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 4

## Finding Actions
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Read-only reentrancy during Balancer exit lets LP collateral be valued at a transiently inflated price | codex_1:0.804 Read-only reentrancy lets Balancer LP collateral be oracle-priced at a transiently inflated value |
| F-002 | rewritten_agent_signal | High | medium | codex_1,opencode_1 | Collateral withdrawal succeeds after manipulated collateral disable without a fresh solvency check | codex_1:0.413 Collateral can be disabled while health checks depend on the manipulated LP price |
| F-003 | rewritten_agent_signal | Medium | high | codex_1 | Anyone can permanently consume the verifier's only execution attempt | codex_1:0.781 Anyone can permanently brick the verifier by consuming its single execution attempt |

## Rejection Reasons
- other: 2
- trust_or_owner_model: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Unprotected Callback enables Permissionless State Change | Not an independent issue: the callback only performs the state change during the contract's own `exitInProgress` window, so arbitrary ETH transfers outside that Balancer-exit callback do nothing. The real reportable problem is the transient-price read-only reentrancy captured in F-001. |
| trust_or_owner_model | codex_1 | Flash-loan callback authorization is incomplete, so third parties can force the verifier to trade with its own balances | Material harm is not supported by the code path. Unauthorized Aave-triggered callbacks are still atomic with the flash loan; unsuccessful paths revert, and no concrete theft or non-reverting loss of verifier-held funds is demonstrated. |
| other | codex_1 | Massive Balancer and Curve exits use effectively zero slippage protection, enabling sandwich-driven value extraction | The reported path does not show a non-reverting loss scenario. MEV can spoil profitability, but the flash-loan-based sequence would then revert atomically rather than force the audited contracts to realize a lasting loss. |
| unsupported_or_speculative | opencode_1 | Missing Reentrancy Guard on Exit Pool Operations | Not supported. The exploit does not rely on re-entering the local helper functions; it relies on observing/manipulating protocol state during Balancer's callback and then calling the lending pool once. |
