# Round 5 Summary

## Agent: codex
- files touched: `src/protocol/pair/ResupplyPairCore.sol`, `src/protocol/ResupplyPair.sol`, `src/protocol/RewardDistributorMultiEpoch.sol`, `src/protocol/WriteOffToken.sol`, `src/interfaces/ICore.sol`
- files revisited / highest-attention files: `src/protocol/pair/ResupplyPairCore.sol` was the main focus, with repeated tracing around borrowing, redemption, liquidation, and reward-accounting paths; `src/protocol/RewardDistributorMultiEpoch.sol` was revisited for reward invalidation behavior
- main issue directions investigated: redemption write-off accounting, reward token invalidation effects, liquidation/redemption settlement assumptions around external handlers, constructor/runtime parameter consistency for max LTV
- promising but not retained directions: handler-trust concerns in `redeemCollateral()` and `liquidate()` were surfaced as draft findings (`F-014`, `F-015`) but were not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: this round’s attention was concentrated in the pair core and reward-distribution boundary, especially redemption accounting and max-LTV initialization
- notable differences in attention: only one agent contributed logs this round, so there was no cross-agent divergence
- underexplored but suspicious files/functions if clearly supported by the logs: external-handler settlement paths in `redeemCollateral()` and `liquidate()` were examined and flagged as plausible concerns in the draft output, but remain unretained in the current round state

## Retained Findings
- `F-013`: retained issue on reward-manager invalidation of the internal `redemptionWriteOff` token breaking redemption-loss accounting and later misallocating skipped write-offs
- `F-016`: retained issue on constructor-time `_maxLTV` assignment bypassing the cap enforced by the runtime setter, allowing unsafe over-100% LTV deployment states
