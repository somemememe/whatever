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
- `FluidEPProgramManager.sol`: persistent hotspot for funding lifecycle/state accounting; cross-round signal now includes shared subsidy-flow bookkeeping across concurrent programs.
- `FluidLocker.sol`: sustained hotspot for staking/LP/reward liveness and FLUID-centric claim/connect assumptions tied to manager configuration.
- `StakingRewardController.sol`: key integration surface for distribution timing and locker unlock/claim behavior.
- `EPProgramManager.sol`: recurring control-plane/auth surface (including durable ID-squatting/timing concerns).
- `FluidLockerFactory.sol`: increasingly relevant for token/pool wiring assumptions that propagate into locker reward behavior.
- `Fontaine.sol` and Superfluid integration (`SuperTokenV1Library.sol`, managers): recurring but mostly integration/coupling context; lower retained exploit signal than manager+locker paths.
- `MacroForwarder.sol`, vesting/peripheral contracts: repeatedly scanned with comparatively low retained signal.

## Issue Directions Seen
- Cross-contract economic/state divergence and liveness failures from tightly coupled accounting/unit dependencies.
- Program-funding lifecycle fragility, including stream/accounting state that can outlive intended program end or mis-handle multi-program shared subsidy flows.
- Token-compatibility drift: permissionless/non-`FLUID` program setup versus FLUID-centric locker claim/connect paths, creating stuck/incompatible reward states.
- Initialization/snapshot ordering hazards (immutable/cached addresses set before full readiness).
- Permissionless control-plane timing games/resource squatting.
- Signature-domain/replay-boundary weakness remains a recurring auth direction, but with weaker recent retention than funding/accounting issues.
- Integration-trust assumptions around cached protocol/framework addresses.

## Useful Context
- Strongest convergence remains end-to-end on `FluidEPProgramManager` + `FluidLocker` (+ controller wiring), not isolated single-contract defects.
- Durable cross-round emphasis has shifted from generic lifecycle concerns to concrete mechanism-level subsidy accounting behavior under concurrent programs.
- Recent broad full-scope reads added coverage but did not materially displace the core hotspot set; retained findings remain concentrated in manager/locker/subsidy interactions.
- Peripheral/library areas are useful for assumptions and blast-radius mapping, but repeatedly produce less retained signal than core funding/reward pathways.


## Latest Round Summary
# Round 5 Summary

## Agent: codex_1
- files touched
  - `FluidEPProgramManager.sol`, `FluidLocker.sol`, `FluidLockerFactory.sol`, plus broad reads across in-scope contracts (`EPProgramManager.sol`, `StakingRewardController.sol`, `Fontaine.sol`, vesting files, `SuperTokenV1Library.sol`, `MacroForwarder.sol`).
- files revisited / highest-attention files
  - `superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol`
  - `superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol`
  - `superfluid-finance/fluid/packages/contracts/src/FluidLockerFactory.sol`
- main issue directions investigated
  - Shared funding-flow accounting and stop/cancel behavior under treasury flow drift.
  - Locker unlock/liveness edge cases from hard minimum thresholds.
  - Liquidity withdrawal min-amount semantics vs internal slippage haircut.
  - ETH fee withdrawal reliability when governor is a contract receiver.
- promising but not retained directions
  - Public initializer takeover risk (`F-021`) was proposed in output but not retained after merge.

## Agent: opencode_1
- files touched
  - Read nearly all in-scope Solidity files, including managers, locker/factory, Fontaine, staking controller, vesting contracts, and interface files.
- files revisited / highest-attention files
  - Attention appeared broad rather than deep; output concentrated on `FluidEPProgramManager.sol`, `FluidLocker.sol`, `StakingRewardController.sol`, `Fontaine.sol`, `SupVestingFactory.sol`.
- main issue directions investigated
  - Program funding duplication, swap slippage, tax distribution timing, final-day termination permissions, event omissions, vesting input validation, ETH transfer behavior.
- promising but not retained directions
  - No unique retained findings from this agent; several reported items overlap prior known findings or were not merged.

## Cross-Agent Status
- main overlap in file/area attention
  - Strong overlap on `FluidEPProgramManager.sol` and `FluidLocker.sol`; both also touched factory-level ETH handling concerns.
- notable differences in attention
  - `codex_1` produced retained findings focused on flow/accounting correctness and withdrawal semantics; `opencode_1` emphasized broader scans and mixed-quality hypotheses (including non-security/known directions).
- underexplored but suspicious files/functions if clearly supported by the logs
  - Despite being read, no retained Round 5 signal emerged from `SupVesting.sol`, `SupVestingFactory.sol`, `MacroForwarder.sol`, or `SuperTokenV1Library.sol` in this round’s merge state.

## Retained Findings
- `F-017`: Treasury flow underflow clamp can zero shared funding stream and disrupt unrelated active programs after flow drift (`FluidEPProgramManager.sol`).
- `F-018`: `FluidLocker.unlock()` minimum 10 SUP threshold can strand sub-threshold balances (`FluidLocker.sol`).
- `F-019`: Liquidity withdrawal applies an extra 5% haircut to caller minima, weakening slippage protection (`FluidLocker.sol`).
- `F-020`: Factory ETH fee withdrawal via `transfer` can lock fees when governor is a contract receiver (`FluidLockerFactory.sol`).


Output only markdown.
