# Merge View - Round 1

## Summary
- total findings: 2
- new findings: 2
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | medium | codex | sDOLA collateral can be overvalued by donating DOLA into the vault/savings path | codex:0.732 sDOLA collateral can be re-priced by donating assets directly to the vault |
| F-002 | rewritten_agent_signal | Critical | medium | codex | Borrow sizing and liquidation are synchronously manipulable through flash-loaned pool and LLAMMA state | codex:0.519 Loan sizing and liquidation depend on flash-loanable spot liquidity from thin pools |

## Rejection Reasons
- other: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Liquidations become executable in the same transaction as the price manipulation | Merged into F-002 as the same root issue: liquidation eligibility and borrow sizing both consume manipulable same-transaction market state. |
| other | codex | Zero-amount LLAMMA exchanges appear to mutate market state for free | The exploit uses zero-amount `exchange` calls as a likely poke, but this file alone does not prove the call changes protocol state in a distinct, reportable way rather than being incidental to the broader oracle/state-manipulation issue. |
