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
- `FluidLocker.sol`: repeated focus on staking/LP accounting coupling, unstake connectivity edge cases, and pump swap execution safety.
- `FluidEPProgramManager.sol`: recurring funding lifecycle control concerns around `startFunding`/`stopFunding` sequencing and residual stream state.
- `EPProgramManager.sol`: signature-domain/replay boundary weaknesses and manager permission flow interactions.
- `Fontaine.sol`: end-of-window permissionless termination behavior repeatedly surfaced as a timing/control pattern.
- `SuperTokenV1Library.sol` (with `EPProgramManager`): persistent concern about cached framework address integrity and possible host/GDA poisoning paths.
- `StakingRewardController.sol`: touched mainly via integration with locker unstake/disconnect behavior; still relatively under-confirmed.
- `SupVesting.sol`, `SupVestingFactory.sol`, `MacroForwarder.sol`: reviewed across rounds but without retained issues so far.

## Issue Directions Seen
- Economic state divergence between staking units and liquidity principal accounting.
- Funding lifecycle idempotency/cleanup failures from repeated start-stop transitions.
- Permissionless or weakly gated control-plane actions in time-gated windows.
- Cross-deployment/cross-chain replay risk from incomplete signature domain separation.
- Slippage/MEV exposure in swap paths lacking explicit execution bounds.
- Integration trust assumptions around cached protocol framework addresses.

## Useful Context
- Cross-agent overlap is strongest in `FluidLocker` and `FluidEPProgramManager`; these remain the most durable risk concentration areas.
- Highest-confidence retained issues are mechanism-level (accounting/control/auth-domain) rather than generic checklist findings.
- Broad-scan claims with weak mechanism grounding were frequently dropped; durable patterns came from deep path tracing across contract interactions.
- Several peripheral contracts were touched but remain underexplored relative to core locker/program-manager pathways.


## Latest Round Summary
# Round 2 Summary

## Agent: codex_1
- files touched  
  `EPProgramManager.sol`, `FluidEPProgramManager.sol`, `FluidLocker.sol`, `StakingRewardController.sol`, `Fontaine.sol` (in findings), plus scoped sweeps including `SuperTokenV1Library.sol`
- files revisited / highest-attention files  
  `FluidLocker.sol`, `StakingRewardController.sol`, `EPProgramManager.sol`
- main issue directions investigated  
  implementation-time state snapshot risks (immutable pool addresses), permissionless program creation behavior, unlock-path liveness conditions tied to pool unit state, funding/flow lifecycle edge cases, numeric cast safety
- promising but not retained directions  
  `FluidEPProgramManager` post-end-date flow overrun (`totalAmount` not auto-enforced), unchecked `uint256 -> uint128` truncation concerns

## Agent: opencode_1
- files touched  
  Full in-scope Solidity set was read, including `EPProgramManager.sol`, `FluidEPProgramManager.sol`, `FluidLocker.sol`, `FluidLockerFactory.sol`, `Fontaine.sol`, `StakingRewardController.sol`, vesting contracts, interfaces, `SuperTokenV1Library.sol`, `MacroForwarder.sol`
- files revisited / highest-attention files  
  `StakingRewardController.sol` (multiple targeted reads around `distributeTaxAdjustment`), `FluidEPProgramManager.sol`
- main issue directions investigated  
  permissionless tax-adjustment execution timing, initialization/order assumptions, vesting edge cases, owner emergency-withdraw effects, liquidity/slippage and observability gaps
- promising but not retained directions  
  vesting lock/withdrawal abuse claims, missing event emission as security issue, owner emergency-withdraw as vulnerability, liquidity-removal slippage concerns, duplicate/overlapping LP pool initialization checks

## Cross-Agent Status
- main overlap in file/area attention  
  Strong overlap on `StakingRewardController.sol` + `FluidLocker.sol` interaction surfaces and `EPProgramManager.sol` program creation logic
- notable differences in attention  
  `codex_1` concentrated on concrete cross-contract state freezing/liveness paths and ID squatting; `opencode_1` cast a wider net across vesting/admin/emergency and operational-pattern issues
- underexplored but suspicious files/functions if clearly supported by the logs  
  `MacroForwarder.sol` and large portions of `SuperTokenV1Library.sol` were read but produced no retained round-2 findings; `Fontaine.sol` appears in retained merged scope mainly via shared pool-address snapshot behavior

## Retained Findings
- `F-009`: retained as medium-confidence architectural risk where Locker/Fontaine implementations can bake stale/zero pool addresses before controller setup completion, breaking unlock/LP/flow paths
- `F-010`: retained medium issue that base `EPProgramManager.createProgram()` allows permanent program ID squatting (no reclaim/delete path)
- `F-011`: retained medium/high-confidence liveness issue where zero-unit tax pools block instant/short unlocks
- `F-012`: retained low-confidence medium issue that permissionless `distributeTaxAdjustment()` can force an unfavorable timing/snapshot allocation of adjustment funds


Output only markdown.
