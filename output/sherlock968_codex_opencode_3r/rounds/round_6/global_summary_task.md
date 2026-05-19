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
- `FluidEPProgramManager.sol`: persistent core hotspot for program funding lifecycle and shared subsidy-flow accounting across concurrent programs; treasury-flow drift interactions remain high-signal.
- `FluidLocker.sol`: sustained hotspot for reward/liveness and withdrawal semantics, including threshold-based unlock stranding and weakened user slippage bounds.
- `FluidLockerFactory.sol`: factory wiring and fee-handling assumptions now carry durable signal, especially ETH fee withdrawal behavior tied to governor receiver type.
- `StakingRewardController.sol`: recurring integration surface for distribution timing and locker claim/unlock coupling.
- `EPProgramManager.sol`: recurring control-plane/auth and timing surface (including ID-squatting style concerns).
- `Fontaine.sol` + Superfluid integration (`SuperTokenV1Library.sol`, manager coupling): repeatedly relevant as dependency context, but lower retained exploit signal than manager/locker/factory paths.
- `MacroForwarder.sol`, vesting/peripheral contracts: repeatedly covered with comparatively low retained signal so far.

## Issue Directions Seen
- Cross-contract accounting/liveness divergence from tightly coupled funding and reward state transitions.
- Shared-stream subsidy fragility: stop/cancel/flow-drift behavior can propagate impact across otherwise unrelated active programs.
- Locker liveness degradation from hard minimum constraints that can strand small residual balances.
- Withdrawal-protection semantics drift where internal haircut/transform of user minima weakens intended slippage guarantees.
- ETH transfer reliability risk from fixed-gas/value-transfer patterns when privileged recipients are contracts.
- Token-compatibility drift between permissionless setup surfaces and FLUID-centric downstream claim/connect assumptions.
- Initialization/snapshot ordering and cached-address trust assumptions remain recurring secondary directions.
- Permissionless control-plane timing/resource-squatting remains a recurring but lower-current-signal direction.

## Useful Context
- Cross-round convergence remains strongest on the end-to-end `FluidEPProgramManager` -> `FluidLocker` -> factory/controller wiring path, not isolated single-contract logic.
- Audit signal has deepened from generic lifecycle concern into concrete mechanism-level failures in shared funding-flow accounting and withdrawal semantics.
- Broad whole-scope rereads continue to expand coverage, but retained findings stay concentrated in manager/locker/factory economic-state interactions.
- Peripheral/integration files remain useful for assumption and blast-radius mapping, yet consistently produce fewer retained issues than core funding/reward pathways.


## Latest Round Summary
# Round 6 Summary

## Agent: codex_1
- files touched: reviewed all in-scope Solidity targets, with explicit deep reads of `EPProgramManager.sol`, `FluidEPProgramManager.sol`, `FluidLocker.sol`; also scanned `SupVesting.sol`, `SupVestingFactory.sol`, `FluidLockerFactory.sol`, `Fontaine.sol`, `StakingRewardController.sol`, interfaces, `SuperTokenV1Library.sol`, `MacroForwarder.sol`
- files revisited / highest-attention files: `EPProgramManager.sol`, `FluidLocker.sol` (nonce/signature + claim flow), plus `SupVestingFactory.sol` for edge-case validation
- main issue directions investigated: signature/nonce handling, claim-path sequencing, public execution frontrun surfaces, `abi.encodePacked` ambiguity risk, zero-address vesting recipient validation
- promising but not retained directions: hash-ambiguity in batch signature packing (`F-021` in agent output) and zero-address vesting creation (`F-023` in agent output) were proposed but not retained after merge

## Agent: opencode_1
- files touched: read all 12 scoped Solidity files (same scope set), plus prior round summary
- files revisited / highest-attention files: broad pass across `FluidLocker.sol`, `StakingRewardController.sol`, `SupVesting.sol`, `FluidEPProgramManager.sol`, `MacroForwarder.sol` (via proposed findings and grep focus)
- main issue directions investigated: event emission gaps, reentrancy markers, pool connection/distribution constants, permissionless calls, access-control consistency, vesting admin/emergency behaviors
- promising but not retained directions: multiple candidate issues were produced (`F-021` to `F-030` in agent output), but none were retained in merged findings

## Cross-Agent Status
- main overlap in file/area attention: strongest overlap on `EPProgramManager.sol` + `FluidLocker.sol` interaction surfaces and permissionless callable functions
- notable differences in attention: `codex_1` focused on concrete claim/nonce exploit path; `opencode_1` emphasized broader hygiene/economic/configuration checks (events, access patterns, parameterization)
- underexplored but suspicious files/functions if clearly supported by the logs: no clear additional hotspot beyond the retained `EPProgramManager`/`FluidLocker` claim path surfaced in merged results

## Retained Findings
- `F-021` (Low, medium confidence): third-party direct execution of signed unit updates can consume nonce before `FluidLocker.claim()` completes pool connection, causing claim revert and temporary reward-flow disruption until reconnection/retry.


Output only markdown.
