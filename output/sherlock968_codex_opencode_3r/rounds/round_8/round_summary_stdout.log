# Round 8 Summary

## Agent: codex_1
- files touched: `EPProgramManager.sol`, `FluidEPProgramManager.sol`, `FluidLocker.sol`, `FluidLockerFactory.sol`, `Fontaine.sol`, `StakingRewardController.sol`, `SupVesting.sol`, `SupVestingFactory.sol`, plus targeted greps over contracts in `superfluid-finance/fluid/packages/contracts/src`
- files revisited / highest-attention files: highest attention on `EPProgramManager.sol`, `FluidEPProgramManager.sol`, and `FluidLocker.sol` (explicit line-level extraction and transfer/flow/distribute pattern tracing)
- main issue directions investigated: nonce validation semantics, unlock/LP gating paths, unit-cast/accounting integrity, locker factory ownership edge cases, vest unlock counter bounds
- promising but not retained directions: LP-fee unlock-gating bypass variant, unchecked `uint128` cast risk, zero-address locker owner creation, `fontaineCount` overflow

## Agent: opencode_1
- files touched: read all in-scope Solidity files (`EPProgramManager.sol`, `FluidEPProgramManager.sol`, `FluidLocker.sol`, `FluidLockerFactory.sol`, `Fontaine.sol`, `StakingRewardController.sol`, interfaces, vesting files, `SuperTokenV1Library.sol`, `MacroForwarder.sol`); also updated round task tracker file
- files revisited / highest-attention files: no clear revisit depth shown; output emphasized `FluidLocker.sol`, `FluidEPProgramManager.sol`, `SupVestingFactory.sol`, `StakingRewardController.sol`
- main issue directions investigated: slippage/front-run themes, emergency withdraw centralization, admin/control-plane risks, flow-rate dependency risks, distribution access-control/economic-timing concerns
- promising but not retained directions: multiple candidates were proposed but not retained after merge (including items overlapping known findings/themes)

## Cross-Agent Status
- main overlap in file/area attention: both focused on `FluidLocker.sol`, `FluidEPProgramManager.sol`, `EPProgramManager.sol`, and vesting/factory surfaces
- notable differences in attention: `codex_1` concentrated on concrete state-machine/accounting invariants (notably nonce progression); `opencode_1` concentrated on broader economic/governance and operational-risk angles
- underexplored but suspicious files/functions if clearly supported by the logs: no new clearly supported hotspot emerged beyond nonce handling; `MacroForwarder.sol` and interface files were read but did not receive deep, evidenced issue development in this round

## Retained Findings
- `F-028` retained: `EPProgramManager` nonce policy (`nonce > lastValidNonce` with stored high-water mark) allows a valid extreme nonce to permanently block future updates for a user/program tuple (irreversible nonce-floor poisoning).
