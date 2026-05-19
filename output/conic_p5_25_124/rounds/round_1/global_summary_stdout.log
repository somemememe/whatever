# Global Audit Memory

## Scope Touched
- `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol`: central execution surface for deposits/withdrawals, rebalancing incentives, ETH/Curve/Convex interaction paths, and possible reentrancy-adjacent behavior
- `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol`: primary reward-accounting hotspot covering checkpointing, zero-stake accrual, extra-reward sale flow, and liability tracking
- `0x635228edaead8a76b6ae1779bd7682043321943d/ConvexHandlerV3.sol`: relevant for extra-reward claim routing and handoff assumptions into reward-manager sale/accounting logic
- Supporting trust-boundary context from `ERC20.sol`, `Ownable.sol`, `IController.sol`, and `LpToken.sol`: background attention on approvals, admin/controller authority, and token accounting assumptions

## Issue Directions Seen
- Reward accounting around sparse or discontinuous staking states, especially zero-stake periods and delayed checkpoint consumption
- Mismatch between claimed rewards, sold rewards, and accounted CNC liabilities across pool and reward-manager boundaries
- Extra-reward handling inconsistencies at the ConvexHandlerV3 -> RewardManagerV2 -> pool handoff, including stranded or unprocessed reward balances
- Incentive design asymmetry in rebalancing flows, with rewardability tied more to deposits than to full capital cycle participation
- Persistent scrutiny on execution-path safety in `ConicEthPool.sol`, especially reentrancy-style exposure, slippage handling, and public path invalidation/depeg edge cases, though several variants were not retained

## Useful Context
- Cross-round attention concentrated most heavily on `ConicEthPool.sol` and `RewardManagerV2.sol`; these remain the core files for both economic and execution-path risk
- The strongest retained themes were economic/accounting inconsistencies rather than pure privilege or generic centralization concerns
- Several non-retained directions still frame ambient context: unsupported extra-reward sale behavior, read-only/callback reentrancy during Curve operations, invalid Convex pid/depeg handling, and approval/admin control surfaces
- A notable pattern is boundary misalignment between where assets are claimed, where balances sit, and where accounting assumes value was realized
