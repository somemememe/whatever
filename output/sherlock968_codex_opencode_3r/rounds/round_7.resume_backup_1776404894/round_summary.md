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
