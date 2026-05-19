# Global Audit Memory

## Scope Touched
- `RewardManagerV2.sol`: central reward-accounting surface; repeated attention on checkpointing, CNC crediting, and where reward balances are observed versus sold
- `ConicEthPool.sol`: main pool state-transition surface; repeated attention on deposits, rebalancing, weight rescaling, and target-selection edge cases
- `ConvexHandlerV3.sol`: key companion in reward flow tracing; claim destination and integration with pool/reward-manager sale paths mattered
- Support layer around the `0xbb...` tree (`ScaledMath.sol`, `LpToken.sol`, `Initializable.sol`, `IController.sol`, interfaces): lightly touched relative to core pool/reward contracts, so still lower-context areas

## Issue Directions Seen
- Reward accounting around zero/empty stake periods is a strong recurring direction
- Reward-claim routing versus sale/accounting location is a strong direction, especially when tokens are claimed outside the balance source later used for sales
- CNC accounting can desync when reward-token sale flows and bookkeeping are not tightly coupled
- Deposit/rebalance logic remains sensitive to rounding and post-rescale allocation edge cases
- Generic surfaces like reentrancy, handler trust, approvals, swap/slippage checks, and oracle dependence were examined but were less substantiated than the reward-flow and allocation issues

## Useful Context
- Cross-round attention concentrated on the flow between `ConicEthPool.sol`, `RewardManagerV2.sol`, and `ConvexHandlerV3.sol`
- The most durable audit pattern is that value/accounting bugs were more promising than generic control-surface concerns
- Reward handling depends materially on which contract actually receives tokens versus which contract later measures balances or credits rewards
- Pool availability and correctness depend on discrete math behavior during rebalance/rescale steps, not just high-level target-weight intent
