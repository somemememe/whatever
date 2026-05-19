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
- `FluidEPProgramManager.sol`: persistent core hotspot for program funding lifecycle, shared subsidy accounting, and residue reconciliation across concurrent programs.
- `FluidLocker.sol`: persistent hotspot for unlock/claim semantics, LP-withdrawal unlock-gating interactions, and signature/nonce sequencing effects.
- `EPProgramManager.sol`: control-plane/timing/auth boundary with manager-locker coupling; now includes durable nonce high-water-mark behavior as a core risk surface.
- `Fontaine.sol` + Superfluid path (`SuperTokenV1Library.sol`, manager coupling): recurring stream-rate/buffer integrity and downstream distribution side effects.
- `FluidLockerFactory.sol` and `StakingRewardController.sol`: integration/wiring and distribution coupling context; recurring but secondary exploit signal.
- `SupVesting.sol` / `SupVestingFactory.sol`: secondary recurring lifecycle edge-case surface (delete/recreate and lockout-style behavior).
- `MacroForwarder.sol` and interfaces/peripherals: repeatedly reviewed, low retained exploit signal.

## Issue Directions Seen
- Cross-contract accounting/liveness divergence from tightly coupled funding and reward state transitions.
- Shared-stream subsidy fragility: requested-vs-actual rate drift and buffer underfunding effects.
- Unlock/withdrawal semantic bypass risk, including LP-path weakening of intended gating.
- Nonce/signature sequencing risks in permissionless execution; now includes irreversible nonce-floor poisoning/high-water-mark griefing pattern.
- Value leakage/drift from clipping, rounding, and tax/distribution transfer semantics.
- Funding lifecycle residue persistence (stranded balances/deposits or incomplete reconciliation).
- Withdrawal-protection/slippage semantic drift via internal minimum/haircut transforms.
- ETH transfer reliability assumptions (fixed-gas/value transfer to contract recipients).
- Token-compatibility and cached-address trust assumptions as recurring secondary directions.

## Useful Context
- Cross-round signal remains concentrated on the end-to-end `FluidEPProgramManager` -> `FluidLocker` -> Superfluid/Factory/Controller path, not isolated single-contract logic.
- Recent rounds mostly reinforced existing themes; the main durable new elevation is nonce policy fragility in `EPProgramManager` (high nonce can permanently block future updates for a tuple).
- Vesting remains secondary but repeatedly surfaces lifecycle lockout-style edge cases after destructive/admin transitions.
- Broad full-scope rereads increased confidence in coverage; retained findings continue clustering in manager/locker economic-state interactions and flow-integrity boundaries.


## Latest Round Summary
# Round 9 Summary

## Agent: codex_1
- files touched: all in-scope Solidity targets were traversed; highest-evidence focus on `FluidEPProgramManager.sol`, `FluidLocker.sol`, `FluidLockerFactory.sol`, and `EPProgramManager.sol`
- files revisited / highest-attention files: `FluidEPProgramManager.sol` (treasury/flow lifecycle), `FluidLocker.sol` (LP withdrawal/tax-free exit state), `FluidLockerFactory.sol` (governor/admin gating)
- main issue directions investigated: funding stream accounting across treasury rotation; liquidity-withdrawal state cleanup and token release paths; factory governance failure modes; signature hashing edge cases
- promising but not retained directions: packed `abi.encodePacked` batch-signature collision concern (`EPProgramManager.sol`) and locker-squatting angle in factory were raised but not retained in merged findings

## Agent: opencode_1
- files touched: read all scoped contracts including vesting, manager, locker/factory, and Superfluid library files
- files revisited / highest-attention files: broad single-pass coverage; notable emphasis in output on `SupVesting.sol`, `SupVestingFactory.sol`, `StakingRewardController.sol`, `FluidEPProgramManager.sol`, and `EPProgramManager.sol`
- main issue directions investigated: admin abuse in vesting emergency flows; permissionless reward-distribution timing; duplicate funding/start checks; batch unit-update/token consistency
- promising but not retained directions: multiple proposed findings overlapped known issues or were weakly supported (including CREATE2/beacon behavior and vesting/admin claims), so none were retained

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on core protocol control planes (`FluidEPProgramManager.sol`, `FluidLocker.sol`, `FluidLockerFactory.sol`, `EPProgramManager.sol`)
- notable differences in attention: codex_1 produced retained flow/accounting and state-lifecycle bugs; opencode_1 leaned toward vesting/admin and timing/governance narratives that were not merged
- underexplored but suspicious files/functions if clearly supported by the logs: `MacroForwarder.sol` and deeper portions of `SuperTokenV1Library.sol` appear lightly examined relative to other files this round

## Retained Findings
- retained set after merge:  
  - `F-029` (Medium): treasury rotation can leave old-treasury funding streams active and unmanaged  
  - `F-030` (Low): early full LP withdrawal can strand withdrawn SUP in locker state flow  
  - `F-032` (Low): `FluidLockerFactory.setGovernor(address(0))` can permanently brick admin controls


Output only markdown.
