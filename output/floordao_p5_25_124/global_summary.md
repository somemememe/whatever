# Global Audit Memory

## Scope Touched
- `contracts/Staking.sol`: central audit surface; repeated attention on warmup stake/claim lifecycle, `rebase()` liability accounting, wrapper conversion paths (`wrap`/`unwrap`), lock toggling, and epoch helper behavior
- `contracts/interfaces/{IDistributor,IERC20,IFloorAuthority,IgFLOOR,IsFLOOR}.sol`: mainly reviewed as dependency/context for staking supply, distributor, and wrapper semantics
- `contracts/libraries/{SafeERC20,SafeMath}.sol`: only surface-level support review; not a primary issue source so far
- `contracts/types/FloorAccessControlled.sol`: background access-control context only; limited direct concern so far

## Issue Directions Seen
- Warmup accounting is the strongest recurring direction: pending warmup balances appear economically entitled yet may be omitted from `rebase()` liability calculations
- Wrapper solvency depends on external supply semantics, especially how `sFLOOR.circulatingSupply()` informs `gFLOOR` backing assumptions
- Warmup position aggregation creates griefing pressure: added stakes can reset or delay effective expiry, with dust/zero-amount interactions increasing the surface
- User-flow edge cases around `toggleLock`, claim behavior, `forfeit`, and mutable warmup configuration recur, but several variants looked more like griefing/UX ambiguity than standalone loss bugs
- `wrap`/`unwrap`, `forfeit`, and `setWarmupLength` remain less fully explored than the main warmup/rebase path

## Useful Context
- Audit attention has been heavily concentrated in `Staking.sol`; non-staking files have mostly served as semantic dependencies rather than independent targets
- Cross-round pattern so far is economic-liability mismatch rather than classic access control or arithmetic failure
- Several initially suspicious edge cases were investigated and not retained, including generic unstake/slippage framing, allowance-only wrapper issues, and helper/comment inconsistencies
- The most durable risk themes are insolvency/backing correctness and griefing via state aggregation, especially where staking state depends on external or configurable semantics
