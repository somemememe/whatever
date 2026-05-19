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
