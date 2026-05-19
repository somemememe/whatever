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
- `FluidLocker.sol`: sustained hotspot for staking/LP accounting coupling, unlock/unstake liveness, and dependency on external pool/unit state.
- `StakingRewardController.sol`: now a core integration surface (not just peripheral), especially tax-adjustment distribution timing and its effects on locker unlockability.
- `FluidEPProgramManager.sol`: recurring concern around funding/stream lifecycle sequencing, cleanup, and residual state across transitions.
- `EPProgramManager.sol`: persistent auth-domain/control-plane focus, now including durable program-creation ID-squatting risk.
- `Fontaine.sol`: repeatedly relevant through timing/control behavior and shared immutable pool-address snapshot coupling with locker/controller setup.
- `SuperTokenV1Library.sol` with program managers: repeatedly reviewed for framework-address trust/caching assumptions; risk direction remains integration-level.
- `MacroForwarder.sol`, vesting contracts, and factory/peripheral files: repeatedly scanned with limited retained security signal so far.

## Issue Directions Seen
- Economic/state divergence and liveness failures from cross-contract unit/accounting dependencies.
- Initialization/snapshot ordering hazards (immutable or cached addresses set before full system readiness).
- Funding lifecycle robustness gaps under repeated start/stop/end transitions and partial cleanup.
- Permissionless control-plane surfaces creating timing games or resource-squatting outcomes.
- Signature-domain/replay-boundary weakness as a recurring auth-direction.
- Integration trust assumptions around cached protocol framework addresses.

## Useful Context
- Strongest cross-round convergence is on `FluidLocker` + `StakingRewardController` + program-manager interactions, not isolated single-contract bugs.
- Highest-confidence retained themes are mechanism-level (state coupling, liveness, control authority, initialization order), while broad operational/checklist claims were often discarded.
- Round-to-round durability improved when traces followed end-to-end flows (controller setup -> pool snapshot -> unlock/distribution behavior).
- Some areas are repeatedly “read but low-yield” (`MacroForwarder`, large `SuperTokenV1Library` portions), suggesting lower current signal versus core locker/program-manager pathways.


## Latest Round Summary
# Round 3 Summary

## Agent: codex_1
- files touched  
  `EPProgramManager.sol`, `IEPProgramManager.sol`, full-scope Solidity set via directory/file sweeps, with focused analysis in `FluidEPProgramManager.sol`; also read prior round/global summaries for targeting.
- files revisited / highest-attention files  
  `FluidEPProgramManager.sol` (funding lifecycle lines around `startFunding`/`stopFunding`), plus follow-up checks touching `FluidLocker.sol`, `FluidLockerFactory.sol`, `StakingRewardController.sol`, and `SupVestingFactory.sol`.
- main issue directions investigated  
  funding stream lifecycle/end-of-program behavior, initializer/upgradeable ownership takeover risk, permissionless claim + nonce-consumption behavior, vesting recipient validation, and ETH withdrawal liveness via `transfer`.
- promising but not retained directions  
  initializer frontrun takeover (`F-014`), forced claim nonce consumption (`F-015`), zero-address vesting recipient burn (`F-016`), and `transfer`-based ETH withdrawal DoS (`F-017`) were proposed by this agent but not retained after merge.

## Agent: opencode_1
- files touched  
  read all in-scope Solidity contracts (program managers, locker/factory, Fontaine, staking controller, vesting, interfaces, `SuperTokenV1Library.sol`, `MacroForwarder.sol`), with an extra targeted read in `SupVestingFactory.sol`.
- files revisited / highest-attention files  
  broad full-scope pass; explicit targeted revisit shown for `SupVestingFactory.sol`.
- main issue directions investigated  
  pumponomics slippage, permissionless funding stop behavior, unlock/distribution timing manipulation, missing event observability, permissionless tax-adjustment timing, and flow-rate truncation.
- promising but not retained directions  
  all reported items in this round output were not retained in the merged retained findings set (including overlap with previously known issues like slippage/permissionless stop/tax-adjustment timing).

## Cross-Agent Status
- main overlap in file/area attention  
  strong overlap on `FluidEPProgramManager.sol` funding lifecycle and broader locker/controller economic-timing surfaces.
- notable differences in attention  
  codex_1 concentrated on a concrete post-end funding overrun mechanism; opencode_1 spread attention across multiple mostly-known or lower-signal directions, including observability/truncation angles.
- underexplored but suspicious files/functions if clearly supported by the logs  
  no clear new underexplored hotspot emerged from this round’s merged evidence; review signal concentrated on `FluidEPProgramManager.startFunding/stopFunding`.

## Retained Findings
- `F-013` retained: `FluidEPProgramManager` funding streams do not auto-terminate at intended program end, so rewards can continue past budget/duration unless an explicit stop/cancel transaction is executed.


Output only markdown.
