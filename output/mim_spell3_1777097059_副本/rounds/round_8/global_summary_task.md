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
- `cauldrons/CauldronV4.sol` remains the dominant surface: `cook()` / `_call()` flexible dispatch and arbitrary-call behavior, `init()` / clone initialization assumptions, solvency-gated borrow/withdraw paths, liquidation seizure/accounting, accrual and debt/share bookkeeping, `withdrawFees()`, `reduceSupply()`, and owner/master-contract parameter storage
- `cauldrons/PrivilegedCauldronV4.sol` remains the main secondary surface, especially `addBorrowPosition()` and privileged debt assignment that can separate debt ownership, MIM extraction, and interest timing
- `cauldrons/PrivilegedCheckpointCauldronV4.sol` still matters mainly for liquidation-hook external interaction and checkpoint-token state coupling, but remains narrower than core cauldron debt/accounting paths
- Supporting interfaces — `interfaces/IOracle.sol`, `interfaces/IBentoBoxV1.sol`, `interfaces/ICheckpointToken.sol`, `interfaces/ISwapperV2.sol`, `interfaces/IStrategy.sol` — continue to matter as assumption surfaces for oracle liveness/decimals, BentoBox share conversions, and external call behavior

## Issue Directions Seen
- `cook()` remains a recurring hotspot because flexible action dispatch, arbitrary external calls, and value forwarding can blur intended safety boundaries
- Initialization and clone lifecycle assumptions remain a live direction: public `init()`, pre-init behavior, and master-vs-clone ownership/state expectations repeatedly attract scrutiny even when specific findings do not stick
- Liquidation logic is a durable high-value direction: accounting consistency, rounding and partial-seizure edges, oracle dependence, and external-hook interactions can turn bad debt handling into revert-driven unliquidatability
- Oracle integration remains a core concern: invalid, stale, reverting, or decimal-mismatched rates can distort or block borrow, withdraw, and liquidation behavior
- Fee and debt accounting mismatches remain promising, especially where bookkeeping for fees, supply reduction, accrual, casts, or debt state diverges from actual BentoBox share availability or effective borrower terms; fee-dust loss on share conversion remains a concrete recurring pattern
- Admin-controlled parameterization remains central: weakly constrained updates to collateralization, interest, liquidation settings, or borrow opening fees can abruptly change solvency and debt economics
- Privileged debt paths continue to stand out where debt can be reassigned or created in ways that separate who receives assets, who bears liabilities, and when interest begins accruing
- Shared-balance / skim mechanics remain dangerous where BentoBox-staged collateral or MIM shares can be relied on by one actor and captured by another

## Useful Context
- Cross-round attention stays concentrated in `CauldronV4`; wrapper cauldrons and interfaces mostly serve as context for validating assumptions around the core debt/accounting engine
- A repeated pattern is internal state appearing coherent while economic reality diverges: collateral may be insufficient to satisfy liquidation math, fee counters may not match withdrawable shares, and debt burden or recoverability can differ materially from stored values
- Post-action assumptions matter more than isolated local checks, especially around oracle failure handling, delayed accrual, BentoBox rounding, cast/order edge cases, liquidation seizure math, and master-vs-clone initialization/ownership assumptions
- Recent review again reinforced suspicion around `init()`, `cook()`, and `_call()` as durable audit magnets, but without newly retained findings; the value is in keeping these surfaces connected to broader accounting and lifecycle themes
- Privileged variants remain less explored overall; `PrivilegedCauldronV4` consistently matters for retained debt/accounting themes, while `PrivilegedCheckpointCauldronV4` remains a narrower external-interaction surface


## Latest Round Summary
# Round 8 Summary

## Agent: codex
- files touched: `cauldrons/CauldronV4.sol`, `cauldrons/PrivilegedCauldronV4.sol`, `cauldrons/PrivilegedCheckpointCauldronV4.sol`, `interfaces/IBentoBoxV1.sol`, `interfaces/IOracle.sol`, `interfaces/ICheckpointToken.sol`, `interfaces/IStrategy.sol`, `interfaces/ISwapperV2.sol`
- files revisited / highest-attention files: `cauldrons/CauldronV4.sol` received the main line-by-line review; `cauldrons/PrivilegedCauldronV4.sol` was revisited for privileged debt-path comparison
- main issue directions investigated: core debt and liquidation accounting, clone initialization safety, privileged borrow/debt paths versus standard cap enforcement, and state-changing entrypoints/invariants around `totalBorrow`, `userBorrowPart`, `userCollateralShare`, and oracle/exchange-rate setup
- promising but not retained directions: a candidate that `PrivilegedCauldronV4.addBorrowPosition()` bypasses global/per-address borrow caps was reported by the agent but was not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: this was a single-agent round, with attention concentrated on `cauldrons/CauldronV4.sol` and the privileged extension path in `cauldrons/PrivilegedCauldronV4.sol`
- notable differences in attention: no cross-agent divergence in this round
- underexplored but suspicious files/functions if clearly supported by the logs: the privileged checkpoint variant and interface files were opened but received far less attention than `CauldronV4.sol`; current round coverage was centered on liquidation, initialization, and privileged debt injection paths

## Retained Findings
- retained a liquidation-accounting issue in `liquidate()` where duplicate borrower entries plus per-iteration floor rounding can let repeated partial liquidations underpay relative to debt cleared
- retained a clone-initialization issue where `init()` is first-caller-wins on uninitialized clones because it lacks an authorized initializer check


Output only markdown.
