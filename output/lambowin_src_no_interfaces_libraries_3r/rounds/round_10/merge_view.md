# Merge View - Round 10

## Summary
- total findings: 21
- new findings: 1
- updated existing findings: 1
- rejected candidates: 8

## Finding Actions
- existing_preserved: 19
- existing_rewritten: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-005 | existing_rewritten | Low | low | codex_1 | Rebalance initialization can be seized if deployment is non-atomic or proxy is left uninitialized | opencode_1:0.432 Initialize Can Be Called By Anyone After Deployment |
| F-021 | rewritten_agent_signal | Low | medium | codex_1 | Initial-buy helper has no caller slippage floor against mutable router fees | codex_1:0.516 Initial buys hardcode zero slippage while mutable fees can take nearly all input |

## Rejection Reasons
- duplicate_or_subsumed: 3
- other: 4
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | Router fee rounding permits per-call fee avoidance on dust-sized trades | The floor-division behavior is real but only avoids fees on dust-sized mainnet trades and is economically immaterial; meaningful fee bypass is already captured by F-011. |
| other | codex_1 | LamboToken implementation can be initialized and minted by anyone | Initializing the implementation affects only the implementation contract's own storage. Factory-created clones have independent storage and are initialized atomically, so this is an off-chain confusion risk rather than protocol-level harm. |
| unsupported_or_speculative | codex_1 | Rebalancer does not clear external OKX token-approve allowances | The concrete in-scope swap path approves the exact input for an exact-input OKX/UniswapV3 swap, so leftover allowance requires speculative external under-consumption or approve-proxy compromise. The code does not support a realistic standalone loss scenario. |
| other | opencode_1 | Initialize Can Be Called By Anyone After Deployment | The claimed clone initialization race is not possible: LamboFactory deploys the clone and calls initialize in the same transaction before any external caller can interact with the new clone address. |
| other | opencode_1 | Factory createLaunchPad Has No Return Value Validation For takeLoan | VirtualToken.takeLoan has no return value and either mints the exact requested amount or reverts on the per-block cap. It cannot silently mint a smaller loan amount. |
| other | opencode_1 | Router Does Not Validate That Pair Exists Before Swap | If the pair does not exist or has no liquidity, getReserves/getAmountOut reverts and the whole transaction rolls back, including the earlier token transfer. This is a revert/UX issue, not fund loss. |
| duplicate_or_subsumed | opencode_1 | Rebalance Allows Zero Amount In With Flash Loan | Zero or near-zero unprofitable calls revert on the profit check, so the protocol does not pay persistent flash-loan costs; the caller bears gas. Arbitrary profitable trade sizing is already captured by F-019. |
| duplicate_or_subsumed | opencode_1 | VirtualToken cashIn Uses msg.value For Non-Native Underlying | This is a duplicate of F-001. The ETH-lock angle is also covered by the same msg.value/accounting bug and by the broader native-ETH recovery issue in F-015. |
