# Global Audit Memory

## Scope Touched
- `contracts/DecentralizedIndex.sol`: central review target across rounds; fee liquidation, reward conversion, rescue/sweep, and `flash()` surfaces keep recurring
- `contracts/TokenRewards.sol`: reward-swap execution, slippage escalation, and conversion timing/MEV are persistent issue areas
- `contracts/WeightedIndex.sol`: bonding/accounting math and price or pair-helper assumptions remain relevant
- `contracts/StakingPoolToken.sol`: staking flow ordering and reentrancy received attention but remain less corroborated
- interface/oracle helper paths (`IDecentralizedIndex`, `ITokenRewards`, `IV3TwapUtilities`, `IUniswapV2Pair`): used mainly to trace pricing, pair existence, and swap assumptions

## Issue Directions Seen
- Public or permissionless swap/liquidation paths with weak execution bounds, especially missing min-out and sandwichable reward conversion
- Reward-swap liveness failures from slippage escalation or brittle execution assumptions, creating stuck or bricked reward flows
- Accounting precision and per-asset rounding risk in bonding/mint flows, especially around `WeightedIndex` collateralization
- Permissionless rescue/sweep behavior that can redirect stray ETH or unsupported tokens to owner-controlled destinations
- Reentrancy and ordering concerns around `flash()` and staking flows were investigated repeatedly, but remain secondary/unretained
- Oracle, TWAP, and pair-existence assumptions surfaced as a recurring caution area around price-dependent paths

## Useful Context
- Cross-round attention is concentrated on `DecentralizedIndex.sol` and `TokenRewards.sol`; most durable concerns sit at the boundary between fee accrual, swaps, and reward distribution
- The audit pattern so far is more economic/execution-risk heavy than pure access-control logic: MEV exposure, slippage handling, liveness, and accounting dominate
- `WeightedIndex.sol` matters mainly where mint/bond math or pricing assumptions feed broader system solvency or fairness
- Several technical directions were explored without retention, but `flash`, `stake`, and pricing-helper paths remain the main underconfirmed suspicious areas
