You maintain a concise global audit memory for future audit agents.

Update the existing global memory by folding in durable observations from the
latest round summary. The goal is an accumulated cross-round audit view, not a
per-round recap.

This memory is optional context only. Findings are stored separately.

Write the updated memory in this exact structure:

# Global Audit Memory

## Scope Touched
- files/contracts/flows that have mattered across rounds, with short issue-direction notes

## Issue Directions Seen
- recurring or promising vulnerability directions seen across the audit

## Useful Context
- compact cross-round observations 

Rules:
- keep it compact
- preserve useful prior context while integrating new durable observations
- prefer stable cross-round patterns over latest-round details
- fold repeated wording into a single clearer observation
- keep the memory descriptive rather than prescriptive

## Existing Global Memory
# Global Audit Memory

## Scope Touched
- `cauldrons/CauldronV4.sol` remains the primary audit surface: `cook()` dispatch/external calls, solvency and accrual flow, borrow/debt accounting, skim-based collateral and repay paths, liquidation accounting, `reduceSupply()`, `withdrawFees()`, initialization, and owner-set risk parameters
- `cauldrons/PrivilegedCauldronV4.sol` remains the main secondary surface, especially `addBorrowPosition()` and privileged debt assignment that can decouple debt ownership, MIM extraction, and interest timing
- `cauldrons/PrivilegedCheckpointCauldronV4.sol` still matters mainly for liquidation-hook external interaction and checkpoint-token state coupling, but remains less central than core cauldron debt/accounting paths
- Supporting interfaces — `interfaces/IOracle.sol`, `interfaces/IBentoBoxV1.sol`, `interfaces/ICheckpointToken.sol`, `interfaces/ISwapperV2.sol`, `interfaces/IStrategy.sol` — matter as assumption surfaces for oracle validity/decimals, shared-balance accounting, and external call behavior

## Issue Directions Seen
- `cook()` remains a recurring hotspot because flexible action dispatch, arbitrary external calls, and value forwarding can blur intended safety boundaries
- Oracle integration remains a durable concern, especially invalid or stale rates and decimal mismatches affecting borrow, withdraw, and liquidation semantics
- Admin-controlled parameterization is now a core issue direction: unbounded updates to collateralization, interest, or liquidation parameters can abruptly change solvency, freeze accrual-dependent flows, or distort liquidation outcomes
- Fee and debt accounting mismatches remain promising, especially where protocol bookkeeping for fees, supply reduction, and debt state diverges from actual MIM/share availability
- Privileged debt paths continue to stand out where debt can be reassigned or created in ways that separate who receives assets, who bears liabilities, and when interest begins accruing
- Shared-balance / skim mechanics remain dangerous where BentoBox-staged collateral or MIM shares can be relied on by one actor and captured by another
- Liquidation logic is still worth attention for accounting consistency, rounding edges, and external-hook interactions

## Useful Context
- Cross-round attention is still concentrated in `CauldronV4`, with most durable themes combining flexible control flow, privileged state mutation, and trust in external components
- A repeated pattern is accounting attribution drifting from asset reality: state can appear internally consistent while fee availability, debt burden, or economic ownership differs materially
- Post-action assumptions matter more than isolated local checks, especially around external interactions, delayed accrual, admin reparameterization, and shared-balance workflows
- Privileged variants remain less explored overall, but `PrivilegedCauldronV4` consistently matters for retained debt/accounting themes, while `PrivilegedCheckpointCauldronV4` remains a narrower external-interaction surface


## Latest Round Summary
# Round 5 Summary

## Agent: codex
- files touched: `cauldrons/CauldronV4.sol`, `cauldrons/PrivilegedCauldronV4.sol`, `cauldrons/PrivilegedCheckpointCauldronV4.sol`, and all scoped interface files under `interfaces/`
- files revisited / highest-attention files: `cauldrons/CauldronV4.sol` dominated review, especially `updateExchangeRate()`, solvency-gated borrow/withdraw flows, `liquidate()`, `cook()`, `withdrawFees()`, and owner/master-contract parameter paths; the two privileged cauldrons were checked more briefly
- main issue directions investigated: oracle failure handling across solvency and liquidation paths; borrow-opening-fee configuration and debt booking; arbitrary-call reach via `cook(ACTION_CALL)`; clone initialization behavior around oracle seeding; master-vs-clone fee/ownership storage assumptions
- promising but not retained directions: `init()` ignoring the oracle success flag and seeding `exchangeRate` from a failed oracle response; `cook(ACTION_CALL)` being able to act on arbitrary ERC-20 balances/allowances held directly by the cauldron

## Cross-Agent Status
- main overlap in file/area attention: only `codex` logged work this round, with attention concentrated on `cauldrons/CauldronV4.sol`
- notable differences in attention: privileged cauldron variants and interface files were reviewed mainly as supporting context rather than primary finding sources
- underexplored but suspicious files/functions if clearly supported by the logs: `cauldrons/CauldronV4.sol` `init()` and `cook(ACTION_CALL)` were investigated enough to produce candidate issues, but neither survived merge this round

## Retained Findings
- retained issues centered on two distinct `CauldronV4` themes: oracle reverts can fully block borrowing, collateral removal, and liquidations, and the borrow-opening fee lacks a sanity cap, allowing confiscatory or effectively unborrowable debt terms after an owner fee update


Output only markdown.
