# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 6

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Borrow and redeem transfer underlying before updating debt/collateral, enabling cross-market reentrancy | codex_1:1.0 Borrow and redeem transfer underlying before updating debt/collateral, enabling cross-market reentrancy |
| F-002 | exact_agent_candidate | High | high | codex_1 | Proxy constructor hands permanent admin rights to `tx.origin` | codex_1:1.0 Proxy constructor hands permanent admin rights to `tx.origin` |
| F-003 | rewritten_agent_signal | Low | medium | codex_1 | Zero-supply reset lets the next minter capture stranded underlying | codex_1:0.838 Zero-supply reset lets the next minter capture stranded cash and future repayments |
| F-004 | rewritten_agent_signal | Medium | medium | codex_1 | Transfer-out accounting is incompatible with fee-on-transfer or deflationary underlyings | codex_1:0.782 Outgoing transfer accounting is incompatible with taxed or fee-on-transfer underlyings |

## Rejection Reasons
- other: 5
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Missing Access Control on _addReservesFresh allows anyone to add reserves | False positive. `_addReservesFresh` is `internal`, and the external `_addReserves` entrypoint is intentionally permissionless reserve donation, not privilege escalation or fund theft. |
| other | opencode_1 | Admin can manipulate initial exchange rate after market is active | Overstated. `_setInitialExchangeRate` is admin-only and does not affect markets while `totalSupply > 0`; once supply is zero there are no incumbent holders to dilute. The reportable edge case is the separate zero-supply stranded-funds capture issue kept above. |
| trust_or_owner_model | opencode_1 | Protocol Seize Share can be set to 100%, breaking liquidation | Admin-only misconfiguration rather than a permissionless exploit. Setting the share to 100% removes liquidator incentive but does not itself create unauthorized fund loss or a code-level bypass. |
| other | opencode_1 | No zero address validation for admin in initialize function | False positive. `initialize` requires `msg.sender == admin`; in the deployed delegator flow the constructor sets `admin = msg.sender` before initialization, and there is no viable path here to initialize with `admin == address(0)`. |
| other | opencode_1 | Missing check for zero reserveFactor in getExp | False positive. `getExp` already propagates `DIVISION_BY_ZERO` via `divUInt`; it does not silently continue with a valid result. |
| other | opencode_1 | Potential rounding error in exchange rate calculation | Non-reportable. Fixed-point truncation is expected in this accounting model and no concrete exploit path or material protocol harm was shown. |
