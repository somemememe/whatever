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
- `cauldrons/CauldronV4.sol` remains the core audit surface, especially `cook()` dispatch/external calls, final solvency checks, borrow/accrual and debt accounting, skim-based collateral/repay flows, liquidation accounting, initialization, and `withdrawFees()`
- `cauldrons/PrivilegedCauldronV4.sol` has become a meaningful secondary surface, centered on `addBorrowPosition()` and privileged debt assignment into downstream MIM extraction / interest-accounting behavior
- `cauldrons/PrivilegedCheckpointCauldronV4.sol` still matters for liquidation-hook external interaction and checkpoint-token state coupling, though it remains lighter-touched than core debt paths
- Supporting interfaces — `interfaces/IOracle.sol`, `interfaces/IBentoBoxV1.sol`, `interfaces/ICheckpointToken.sol`, `interfaces/ISwapperV2.sol`, `interfaces/IStrategy.sol` — continue to matter mainly as assumption surfaces for oracle validity/decimals, shared-balance accounting, and external call behavior

## Issue Directions Seen
- `cook()` remains a recurring hotspot: flexible action dispatch, arbitrary external call capability, ETH/value forwarding, and whether auxiliary actions can weaken intended safety boundaries
- Oracle integration remains a durable cross-cutting concern, especially zero/invalid rates, stale pricing, and decimal mismatches affecting borrow, withdraw, and liquidation semantics
- Debt-accounting privilege paths now stand out: privileged debt can be assigned or reshaped in ways that separate who receives MIM, who carries debt, and when interest starts accruing
- Shared-balance / skim mechanics look consistently dangerous where public or non-atomic workflows rely on BentoBox-staged collateral or MIM shares that other actors can capture
- Liquidation logic is still promising for accounting-consistency and external-hook edge cases, especially where external checkpoint behavior can perturb expected state

## Useful Context
- Cross-round attention is still concentrated in `CauldronV4`, with most durable themes combining flexible control flow, privileged state mutation, and trust in external components
- A repeated pattern is mismatch between accounting attribution and asset movement: protocol state can look internally consistent while economic ownership or timing assumptions break
- Post-action safety assumptions matter more than isolated local checks, especially around external interactions, delayed accrual, and shared-balance workflows
- Privileged variants remain less explored overall, but `PrivilegedCauldronV4` now matters more for retained debt/accounting themes, while `PrivilegedCheckpointCauldronV4` remains a secondary external-interaction surface


## Latest Round Summary
# Round 4 Summary

## Agent: codex
- files touched: `cauldrons/CauldronV4.sol`, `cauldrons/PrivilegedCauldronV4.sol`, `cauldrons/PrivilegedCheckpointCauldronV4.sol`, and all scoped interface files under `interfaces/`
- files revisited / highest-attention files: `cauldrons/CauldronV4.sol` received the bulk of line-by-line review, especially solvency, accrue, liquidation, fee withdrawal, supply reduction, and owner parameter setters; `cauldrons/PrivilegedCauldronV4.sol` and `cauldrons/PrivilegedCheckpointCauldronV4.sol` were checked more briefly
- main issue directions investigated: unsafe owner-controlled risk parameter updates (`COLLATERIZATION_RATE`, `INTEREST_PER_SECOND`, `LIQUIDATION_MULTIPLIER`), fee-accounting consistency between `reduceSupply()` and `withdrawFees()`, privileged debt/accounting paths, clone initialization access, and liquidation rounding behavior
- promising but not retained directions: hostile first-initialization of orphaned clones via public `init()`, and per-account rounding dust in batch liquidation; both appeared in the agent output but were not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: single-agent round; attention was concentrated on `cauldrons/CauldronV4.sol` core state-transition logic
- notable differences in attention: wrappers and interfaces were inspected mainly as support context, with far less attention than the main cauldron
- underexplored but suspicious files/functions if clearly supported by the logs: `cauldrons/CauldronV4.sol` `init()` and liquidation rounding paths were examined enough to surface candidate issues but did not survive merge; `cauldrons/PrivilegedCauldronV4.sol` was reviewed, but no retained finding came from that path this round

## Retained Findings
- retained issues centered on unbounded admin-set parameters in `CauldronV4`: collateralization-rate changes can swing the market into free-borrow or forced-liquidation states, interest-rate changes can brick `accrue()` and freeze core operations, and liquidation-multiplier changes can either block liquidations or over-seize collateral
- one retained accounting issue remained around `reduceSupply()` not reserving MIM that `withdrawFees()` still treats as earned fees, enabling fee shortfall or confiscation of accrued protocol revenue


Output only markdown.
