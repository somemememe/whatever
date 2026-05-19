# Global Audit Memory

## Scope Touched
- `yETH.sol` — dominant focus across the audit so far; liquidity accounting, `update_rates` behavior, repeated `remove_liquidity(0, ...)`, and OETH rebase interaction appear central to exploitability
- liquidity settlement flow in `yETH.sol` — attention centers on basket valuation during withdrawals when rate refreshes are selective or inconsistent
- zero-burn / zero-amount withdrawal path — `remove_liquidity(0)` repeatedly appears as a potentially stateful accounting transition without corresponding burn cost
- OETH balance-sync path — `OETH.rebase()` may change effective balances outside cached pool accounting assumptions

## Issue Directions Seen
- Mixed stale/fresh asset-rate accounting during liquidity operations is the strongest recurring direction, especially where attackers may influence which rates are refreshed before settlement
- Selective `update_rates` usage is suspicious less as a standalone stale-price bug and more as a way to create inconsistent basket pricing within one settlement path
- Zero-amount liquidity removal may act as a free accounting-state transition primitive that helps stage or extract value in exploit sequences
- External rebasing of held assets can desynchronize real balances from cached accounting and interact dangerously with settlement logic

## Useful Context
- Audit attention is highly concentrated in `yETH.sol`; no other files have yet contributed durable cross-round context
- The most durable framing is accounting inconsistency across liquidity operations rather than isolated stale-rate observations
- Exploit reconstruction repeatedly ties together three elements: selective rate refresh, `remove_liquidity(0)` transitions, and OETH rebasing effects
- Exploit-helper phases were mainly evidence trails; the enduring audit value is in the core settlement and accounting paths they expose
