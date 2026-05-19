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
- `FluidEPProgramManager.sol`: persistent core hotspot for funding lifecycle and shared subsidy-flow accounting across concurrent programs; treasury/flow-drift interactions remain high-signal.
- `FluidLocker.sol`: sustained hotspot for reward liveness and withdrawal semantics; now also a concrete nonce/signature-claim sequencing surface with temporary claim disruption risk.
- `EPProgramManager.sol`: recurring control-plane/auth/timing surface; repeatedly overlaps with locker claim/update execution paths and permissionless callable boundaries.
- `FluidLockerFactory.sol`: factory wiring and fee-handling assumptions remain durable, including ETH fee withdrawal behavior when governor receivers are contracts.
- `StakingRewardController.sol`: recurring integration surface for distribution timing and locker claim/unlock coupling.
- `SupVesting.sol` / `SupVestingFactory.sol`: repeatedly checked for recipient/admin edge cases, but retained signal remains secondary.
- `Fontaine.sol` + Superfluid integration (`SuperTokenV1Library.sol`, manager coupling): useful dependency context with lower retained exploit signal than manager/locker/factory paths.
- `MacroForwarder.sol` and other peripherals: repeatedly covered with comparatively low retained signal.

## Issue Directions Seen
- Cross-contract accounting/liveness divergence from tightly coupled funding and reward state transitions.
- Shared-stream subsidy fragility where stop/cancel/flow-drift behavior can affect otherwise unrelated active programs.
- Permissionless execution + nonce/signature sequencing risk: third-party execution can consume/update state before downstream claim steps complete, creating temporary reward-flow disruption.
- Locker liveness degradation from hard minimum constraints that can strand residual balances.
- Withdrawal-protection semantics drift where internal haircut/transform of user minima weakens intended slippage guarantees.
- ETH transfer reliability risk from fixed-gas/value-transfer patterns when privileged recipients are contracts.
- Token-compatibility drift between permissionless setup surfaces and FLUID-centric downstream claim/connect assumptions.
- Initialization/snapshot ordering and cached-address trust assumptions remain recurring secondary directions.
- Broader hygiene directions (event completeness, generic reentrancy markers, encode-packing ambiguity, zero-address vesting setup) were repeatedly explored with lower retained signal.

## Useful Context
- Cross-round convergence remains strongest on the end-to-end `FluidEPProgramManager` -> `FluidLocker` -> factory/controller wiring path, not isolated single-contract logic.
- A durable new concrete pattern is claim-path sequencing fragility: nonce/state can be consumed before pool connection/claim completion, causing retry-dependent temporary disruption rather than permanent loss.
- Repeated full-scope rereads continue to broaden coverage, but retained findings stay concentrated in manager/locker economic-state interactions and permissionless execution surfaces.
- Peripheral/integration files remain useful for assumption and blast-radius mapping, yet consistently produce fewer retained issues than core funding/reward pathways.


## Latest Round Summary
# Round 7 Summary

## Agent: codex_1
- files touched  
  `FluidLocker.sol`, `FluidEPProgramManager.sol`, `Fontaine.sol`, `SupVesting.sol`, `SupVestingFactory.sol`, `EPProgramManager.sol`, `SuperTokenV1Library.sol` (plus scope enumeration across all `.sol` files)
- files revisited / highest-attention files  
  `FluidLocker.sol` and `FluidEPProgramManager.sol` were the main focus, with repeated linkage to `Fontaine.sol` and `SuperTokenV1Library.sol`
- main issue directions investigated  
  unlock-path bypasses via LP flows, requested-vs-actual GDA accounting mismatches, Superfluid buffer underfunding in streaming setups, clipped tax distribution leakage, program funding residue handling, vesting lifecycle edge cases
- promising but not retained directions  
  “pool units drop to zero after startFunding and strand active funding” appeared in agent output but was not retained after merge as a final finding

## Agent: opencode_1
- files touched  
  Read all in-scope contracts, including `EPProgramManager.sol`, `FluidEPProgramManager.sol`, `FluidLocker.sol`, `Fontaine.sol`, `StakingRewardController.sol`, `FluidLockerFactory.sol`, `SupVesting.sol`, `SupVestingFactory.sol`, `SuperTokenV1Library.sol`, `MacroForwarder.sol`; also ran targeted greps
- files revisited / highest-attention files  
  Broad scan pattern; strongest apparent attention on `FluidLocker.sol` and `FluidEPProgramManager.sol` based on reported issue list
- main issue directions investigated  
  access control surfaces, reentrancy/flow operations, funding lifecycle, tax/distribution behavior, signature/nonce handling
- promising but not retained directions  
  No round-retained findings sourced from this agent; reported set largely overlapped prior known issues or did not survive merge

## Cross-Agent Status
- main overlap in file/area attention  
  Strong overlap on `FluidLocker.sol`, `FluidEPProgramManager.sol`, `Fontaine.sol`, and Superfluid flow/distribution mechanics (`SuperTokenV1Library.sol`)
- notable differences in attention  
  `codex_1` concentrated on new accounting/flow-integrity edge cases and vesting/Fontaine consequences; `opencode_1` performed wider grep-led coverage and surfaced many already-known directions
- underexplored but suspicious files/functions if clearly supported by the logs  
  Relative to retained outcomes, `FluidLockerFactory.sol`, `MacroForwarder.sol`, and most of `StakingRewardController.sol` had limited retained-depth coverage this round

## Retained Findings
- Retained set includes 6 merged findings: one High (`F-022`) and five lower-severity (`F-023` to `F-027`)
- Core retained themes were: unlock-gating bypass via LP withdrawal path, Superfluid buffer underfunding in unlock/vesting streams, requested-vs-actual GDA rate mismatch effects, clipped tax distribution value leaking back to unlock recipients, program funding deposit residue persistence, and vesting recreation lockout after emergency deletion


Output only markdown.
