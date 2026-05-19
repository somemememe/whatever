# Round 1 Summary

## Agent: codex_1
- files touched: `onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol`
- files revisited / highest-attention files: repeated chunked and line-numbered review of `onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol`, with concentration around flash-loan callback, deposit/withdraw, Curve swap, and pause paths
- main issue directions investigated: Balancer flash-loan callback authorization, idle ETH/NAV accounting, withdrawal payout logic, zero-`min_dy` Curve execution, and stETH depeg / liquidity-driven withdrawal failure
- promising but not retained directions: none clearly shown beyond the retained set

## Agent: opencode_1
- files touched: `onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol`, `onchain_auto/src/FlawVerifier.sol`
- files revisited / highest-attention files: `onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol`, especially `getVirtualPrice`, `getDebt`, and `getCollecteral` via targeted grep
- main issue directions investigated: share-price / accounting edge cases, reward math, owner `delegatecall` power, Curve slippage, withdrawal accounting, and LTV adjustment access control
- promising but not retained directions: division-by-zero in `getVirtualPrice` and `_earnReward`, owner abuse via `callWithData`, debt/redemption mismatch in `_withdraw`, fee config / hardcoded address concerns, and public `reduceActualLTV` / `raiseActualLTV`

## Cross-Agent Status
- main overlap in file/area attention: both agents focused on `onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol`, with overlap on withdrawal behavior and zero-slippage Curve swaps
- notable differences in attention: `codex_1` concentrated on end-to-end exploitability around flash loans, idle ETH, and lockup paths; `opencode_1` spent more attention on arithmetic edge cases, admin capability, and access control, and also read `onchain_auto/src/FlawVerifier.sol`
- underexplored but suspicious files/functions if clearly supported by the logs: current logs show single-agent scrutiny on `getVirtualPrice`, `_earnReward`, `callWithData`, `reduceActualLTV`, and `raiseActualLTV`, but none of those were retained after merge

## Retained Findings
- Retained issues center on a connected exploit surface in the vault: unauthorized Balancer callback execution can force rebalancing, idle ETH is misaccounted in share pricing, and unpaused withdrawals can transfer the full ETH balance rather than a proportional amount
- The round also retained market-execution risk from Curve swaps using `min_dy = 0`
- A separate retained risk is loss of exitability: withdrawals and even `pause()` can fail under stETH depeg or severe Curve illiquidity
