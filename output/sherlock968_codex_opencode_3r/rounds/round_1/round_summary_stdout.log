# Round 1 Summary

## Agent: codex_1
- files touched: all in-scope Solidity files, with explicit deep reads on `FluidLocker.sol`, `FluidEPProgramManager.sol`, `EPProgramManager.sol`, `Fontaine.sol`, `FluidLockerFactory.sol`, and `SuperTokenV1Library.sol`
- files revisited / highest-attention files: `FluidLocker.sol`, `FluidEPProgramManager.sol`, `EPProgramManager.sol`, `SuperTokenV1Library.sol`
- main issue directions investigated: staking vs LP accounting interactions, funding lifecycle controls (`startFunding`/`stopFunding`), signature-domain/replay safety, swap slippage/MEV exposure, permissionless early termination behavior, framework address caching risks
- promising but not retained directions: `FluidLockerFactory.withdrawETH()` gas-stipend/`transfer` stuck-ETH concern (reported by codex_1 but not retained)

## Agent: opencode_1
- files touched: all 12 scoped `.sol` files (broad full-pass read)
- files revisited / highest-attention files: `FluidEPProgramManager.sol`, `FluidLocker.sol`, `Fontaine.sol`, plus broad attention to `StakingRewardController.sol`, `SupVesting*.sol`, `MacroForwarder.sol`
- main issue directions investigated: missing access control, repeated funding lifecycle behavior, partial-unstake pool connectivity, generic reentrancy/event/precision/permission-model checks
- promising but not retained directions: multiple high/critical claims were dropped at merge (e.g., reentrancy in `withdrawLiquidity`, missing event as security issue, MacroForwarder permissionless usage, vesting math/approval concerns, tax distribution access-control framing)

## Cross-Agent Status
- main overlap in file/area attention: strong overlap on `FluidEPProgramManager.sol` (`stopFunding`, repeated `startFunding`) and `Fontaine.sol` early termination; both also examined `FluidLocker.sol`
- notable differences in attention: codex_1 contributed most retained deep-mechanism findings (rehypothecation, replay across deployments/chains, pump slippage, SuperToken cache poisoning), while opencode_1 produced a wider but noisier surface scan
- underexplored but suspicious files/functions if clearly supported by the logs: `SupVesting.sol`, `SupVestingFactory.sol`, `MacroForwarder.sol`, and parts of `StakingRewardController.sol` were reviewed but ended this round without retained issues

## Retained Findings
- high-severity economic/accounting break: staked FLUID can be reused for LP principal while staking units remain active (`FluidLocker`)
- high-severity control-plane issue: `stopFunding` can be triggered by anyone during early-end window (`FluidEPProgramManager`)
- medium-severity auth-domain issue: unit-update signatures are replayable across deployments/chains (`EPProgramManager`)
- medium-severity flow-accounting issue: repeated `startFunding` can leave residual treasury/subsidy streams after stop/cancel (`FluidEPProgramManager`)
- medium-severity MEV exposure: pump swap executes without slippage floor (`FluidLocker`)
- low-severity timing/control issue: any account can terminate Fontaine unlocks in final-day window (`Fontaine`)
- low-confidence medium risk: permissionless manager flow may allow SuperToken host/GDA cache poisoning (`EPProgramManager` + `SuperTokenV1Library`)
- low-severity behavior mismatch: partial `unstake` disconnects locker despite remaining staker units (`FluidLocker`/`StakingRewardController`)
