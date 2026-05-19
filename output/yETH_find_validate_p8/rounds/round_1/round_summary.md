# Round 1 Summary

## Agent: codex
- files touched: `yETH.sol`
- files revisited / highest-attention files: `yETH.sol`, especially the exploit sequence, `update_rates` call sites, repeated `remove_liquidity(0, ...)` usage, and the `OETH.rebase()` step
- main issue directions investigated: stale cached rate usage during liquidity ops; attacker-selected partial rate refreshes creating mixed stale/fresh basket valuation; zero-amount `remove_liquidity` as a possibly stateful accounting transition; rebasing OETH changing balances outside cached accounting
- promising but not retained directions: a standalone “stale cached rates” finding was explored separately, but after merge the retained framing centers on mixed stale/fresh asset-rate settlement rather than keeping stale-rate-only and partial-update issues as separate findings

## Cross-Agent Status
- main overlap in file/area attention: only one agent participated; attention concentrated on `yETH.sol` liquidity accounting, selective rate updates, zero-burn withdrawals, and rebase interaction
- notable differences in attention: none in this round
- underexplored but suspicious files/functions if clearly supported by the logs: no additional files were explored; within `yETH.sol`, the exploit-helper phases were mostly used as evidence trails, while `update_rates`, `remove_liquidity(0)`, and the OETH rebase path received the clearest focused attention

## Retained Findings
- Mixed stale/fresh asset-rate accounting remained the core critical issue after merge, covering selective refresh behavior and liquidity settlement against inconsistent basket pricing
- `remove_liquidity(0)` was retained as a high-severity, low-confidence indication of a free accounting-transition primitive used in the exploit flow
- Rebasing OETH remained retained as a high-severity accounting-sync issue where external balance changes may diverge from cached pool state
