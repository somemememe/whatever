# Global Audit Memory

## Scope Touched
- `0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/token/Usd0PP.sol` — primary audit surface; redemption, unwrap, upgrade, and bond-lifecycle logic repeatedly concentrated here
- `0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/interfaces/token/IUsd0PP.sol` — used as the main spec/reference point for code-vs-interface behavior mismatches
- `0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/constants.sol` — relevant for protocol configuration assumptions around timing and token dependencies
- OZ helpers `SafeERC20.sol` / `Address.sol` — checked only insofar as helper-call semantics could affect token interaction assumptions

## Issue Directions Seen
- Upgrade/reinitializer safety around `Usd0PP` dependency wiring, especially initialization order and whether a frontrunner can seize critical dependency state
- Split-claim / backing-release risks in bond or redemption flows, where one side of a paired position may unlock value without the other side being extinguished
- Bond mint / deconstruct / reconstruct / unwrap paths as the main economic-consistency surface
- Persistent code/spec drift checks, especially around bond timing, early unlock behavior, and documented gating conditions
- Secondary but unresolved scrutiny around `unlockUSD0ppWithUsual`, `sweepFees`, and start-time gating logic

## Useful Context
- The audit’s first-round attention was heavily concentrated in `Usd0PP.sol`; this contract is the durable center of risk and review context
- Interface/spec comparison mattered repeatedly, suggesting documentation and declared behavior are not fully reliable proxies for implementation
- Two strongest retained themes were mis-sequenced upgrade initialization and redemption/accounting asymmetry between paired bond claims
- Helper-library review did not become a standalone issue area; it mainly served to validate assumptions around token-call behavior in `Usd0PP` flows
