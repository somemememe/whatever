# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- exact_agent_candidate: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | Thin-market donation inflation lets an attacker steal later deposits | codex_1:1.0 Thin-market donation inflation lets an attacker steal later deposits |
| F-002 | exact_agent_candidate | High | medium | codex_1 | Borrow and redeem transfer out underlying before updating debt or collateral, enabling cross-market reentrancy with callback tokens | codex_1:0.981 Borrow and redeem transfer out underlying before updating debt/collateral, enabling cross-market reentrancy with callback tokens |
| F-003 | exact_agent_candidate | Medium | high | codex_1 | Small `redeemUnderlying` calls can withdraw underlying while burning zero cTokens | codex_1:1.0 Small `redeemUnderlying` calls can withdraw underlying while burning zero cTokens |

## Rejection Reasons
- low_impact_or_operational: 1
- other: 7

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Flash Loan Attack on Exchange Rate During Mint | Misreads the code path: `mintFresh()` reads the exchange rate before `doTransferIn()` at line 1594, not after. The real issue is donation-driven exchange-rate inflation, which is captured separately. |
| other | opencode_1 | Flash Loan Attack on Exchange Rate During Redeem | Changing cash after `redeemFresh()` computes `redeemAmount` does not increase the already-fixed payout. The plausible issue here is stale-state reentrancy during `doTransferOut()`, captured separately. |
| other | opencode_1 | Missing Zero-Address Validation on Initialize | Initializing with zero comptroller or interest model does not silently succeed: `_setComptroller()` and `_setInterestRateModelFresh()` call marker methods that revert on invalid addresses. This is not a distinct exploit. |
| other | opencode_1 | Unsafe ERC-20 Approval Pattern | This is the standard ERC-20 allowance overwrite behavior on the cToken share token, explicitly documented in the code comments. It is a known user-level caveat, not a protocol-specific vulnerability. |
| other | opencode_1 | Admin Can Set Arbitrary Initial Exchange Rate | This is a trusted deployment/configuration parameter chosen at market creation, not a permissionless exploit against deployed users. |
| other | opencode_1 | Potential State Manipulation Through Block Delta | Depends on mocked or test-only `getBlockNumber()` behavior rather than a realistic deployed attack path. |
| low_impact_or_operational | opencode_1 | Missing Event Emission on Initialize | Operational/informational observation only; no realistic protocol harm. |
| other | opencode_1 | Deprecated Solidity Version | Generic technical-debt note, not a concrete vulnerability in this codebase. |
