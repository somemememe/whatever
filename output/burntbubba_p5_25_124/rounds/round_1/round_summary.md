# Round 1 Summary

## Agent: codex_1
- files touched: `contracts/FSushiBill.sol`, `contracts/FSushiCookV0.sol`, `contracts/SousChef.sol`, `contracts/FarmingLPToken.sol`, `contracts/libraries/UniswapV2Utils.sol`, `contracts/FlashStrategySushiSwap.sol`, `contracts/FSushiBar.sol`, `contracts/libraries/FSushiBarPriorityQueue.sol`, `contracts/libraries/Snapshots.sol`, `contracts/FSushiKitchen.sol`, `contracts/FSushiAirdropsVotingEscrow.sol`
- files revisited / highest-attention files: `FSushiBill.sol`, `FarmingLPToken.sol`, `FSushiBar.sol`, `FSushiAirdropsVotingEscrow.sol`
- main issue directions investigated: bill accounting and reward checkpointing, fLP reward-debt/share accounting, quote-based LP valuation, flash-strategy principal accounting, bar lock/share consistency, historical snapshot lookup, historical ve-airdrop reconstruction
- promising but not retained directions: none clearly visible beyond the retained set

## Agent: opencode_1
- files touched: `contracts/FSushi.sol`, `contracts/FSushiBar.sol`, `contracts/FSushiBill.sol`, `contracts/FarmingLPToken.sol`, `contracts/SousChef.sol`, `contracts/FlashStrategySushiSwap.sol`, `contracts/FSushiKitchen.sol`, `contracts/FSushiAirdrops.sol`, `contracts/FSushiAirdropsVotingEscrow.sol`, `contracts/base/BaseERC20.sol`, `contracts/libraries/FSushiBarPriorityQueue.sol`, `contracts/FlashStrategySushiSwapFactory.sol`
- files revisited / highest-attention files: `FSushiAirdropsVotingEscrow.sol`, `FarmingLPToken.sol`, `FSushiBar.sol`, `FSushiBarPriorityQueue.sol`
- main issue directions investigated: division/arithmetic failure cases, timestamp-collision behavior in the bar queue, withdrawal/accounting edge cases, factory/access-control and claim-path sanity checks
- promising but not retained directions: `FSushiBar.sol` initial-state deposit logic, several `FarmingLPToken.sol` precision/fee/emergency-withdraw ideas, `FSushiAirdrops.sol` zero-address claim sink, `FlashStrategySushiSwapFactory.sol` permissionlessness, long-tail ve-airdrop arithmetic concerns

## Cross-Agent Status
- main overlap in file/area attention: both agents focused on `FSushiBar.sol` plus `FSushiBarPriorityQueue.sol`, `FarmingLPToken.sol`, and `FSushiAirdropsVotingEscrow.sol`; the shared retained overlap was the same-timestamp queue overwrite issue
- notable differences in attention: `codex_1` went deeper on reward-accounting flows across `FSushiBill`, `FSushiCookV0`, `SousChef`, `FSushiKitchen`, `Snapshots`, and `FlashStrategySushiSwap`; `opencode_1` ran a broader arithmetic/edge-case pass across core contracts and surfaced more non-retained candidates
- underexplored but suspicious files/functions if clearly supported by the logs: `FSushiAirdrops.sol`, `FlashStrategySushiSwapFactory.sol`, and `base/BaseERC20.sol` were touched but did not produce retained findings this round

## Retained Findings
- Retained findings concentrated in four clusters: `FSushiBill` reward/accounting corruption, `FarmingLPToken` reward/share and exit-path bugs, `FSushiBar` lock bookkeeping failures, and `FSushiAirdropsVotingEscrow` historical-claim breakage.
- The merged set kept 11 findings, including critical issues around backdated rewards, duplicated reward entitlements, principal depletion in the flash strategy, and broken historical checkpoint/snapshot logic.
- One issue was independently reinforced across agents: `FSushiBarPriorityQueue` overwriting same-timestamp snapshots and losing deposits.
