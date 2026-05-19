# Global Audit Memory

## Scope Touched
- `single-sided-lp/AbstractSingleSidedLP.sol`, `single-sided-lp/CurveConvex2Token.sol`: Curve V2 liquidation precheck/liveness behavior.
- `rewards/AbstractRewardManager.sol`, `rewards/RewardManagerMixin.sol`, `rewards/ConvexRewardManager.sol`: reward accumulator/debt correctness across claim, update, and migration timing.
- `withdraws/AbstractWithdrawRequestManager.sol`, `withdraws/Ethena.sol`, `withdraws/Dinero.sol`, `withdraws/GenericERC4626.sol`, `withdraws/Origin.sol`: pending-withdraw valuation semantics, async finalization accounting, and gas-bounded finalize loops.
- `routers/AbstractLendingRouter.sol`, `routers/MorphoLendingRouter.sol`: health/authorization assumptions and migration rounding underfunding edges.
- `oracles/AbstractLPOracle.sol`, `oracles/AbstractCustomOracle.sol`, `staking/AbstractStakingStrategy.sol`, `staking/PendlePT.sol`, `staking/PendlePTLib.sol`, `proxy/AddressRegistry.sol`, `proxy/TimelockUpgradeableProxy.sol`: broad review pass with no newly retained direction in this round.

## Issue Directions Seen
- Liquidation flow liveness can break when strict prechecks gate external unwind paths.
- Reward accounting remains sensitive to claim/update ordering, failed transfer handling, and migration windows.
- Async withdraw pipelines can misprice pending value versus realized assets (including ETH/WETH leg handling).
- Finalization paths with loop/gas pressure can cause liveness and accounting drift.
- Router migration rounding can leave small but compounding underfunded positions.

## Useful Context
- Round 5 retained findings were F-016 to F-024 (9 total), concentrated in rewards, withdraw lifecycle, Curve single-sided LP, and Morpho migration.
- Cross-agent overlap was highest in rewards/withdraw/router/LP areas; retained output came from `codex_1`, while `opencode_1` mostly overlapped prior directions.
- Highest-attention continuity files: `rewards/AbstractRewardManager.sol`, `withdraws/AbstractWithdrawRequestManager.sol`, `withdraws/Dinero.sol`, `single-sided-lp/CurveConvex2Token.sol`, `routers/MorphoLendingRouter.sol`.
