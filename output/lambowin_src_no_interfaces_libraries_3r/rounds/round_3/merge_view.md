# Merge View - Round 3

## Summary
- total findings: 8
- new findings: 2
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- existing_preserved: 6
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-007 | rewritten_agent_signal | High | high | codex_1 | Predictable clone address enables pair pre-creation that can indefinitely brick targeted launch attempts | codex_1:0.505 Predictable clone address allows permanent launchpad bricking via pre-created pair |
| F-008 | rewritten_agent_signal | Low | medium | codex_1,opencode_1 | Rebalance ignores caller-provided output target and executes swaps with zero minimum return | codex_1:0.759 Rebalance ignores caller slippage input and executes swaps with minReturn=0 |

## Rejection Reasons
- duplicate_or_subsumed: 1
- low_impact_or_operational: 1
- other: 7
- trust_or_owner_model: 1
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex_1 | Router fee transfer hard-dependency can halt all buys and sells | Requires privileged owner misconfiguration/intentional behavior; owner already has direct control over trading parameters, so this is not a distinct external exploit. |
| low_impact_or_operational | codex_1 | Unvalidated directionMask can produce malformed pool encoding in flashloan callback | Malformed masks mainly cause caller-side reverts/self-grief; no convincing shared-state corruption or protocol-level loss path was supported. |
| other | codex_1 | LamboToken implementation contract can be initialized and minted by anyone | Affects only the standalone implementation instance, not factory-created clones; no protocol fund or permission impact beyond potential off-chain confusion. |
| other | opencode_1 | Rebalance profit calculation includes user-provided ETH wrapped as WETH | The code subtracts `initialBalance` before wrapping (`newBalance = address(this).balance - initialBalance`), so pre-existing ETH is not counted as profit in the stated way. |
| other | opencode_1 | Router missing deadline parameter enabling transaction reordering | Users already have slippage protection via `minReturn`; missing deadline alone is not a concrete, distinct protocol vulnerability here. |
| other | opencode_1 | Rebalance can be DoS'd by reverting onMorphoFlashLoan callback | Reverting callback only reverts the attacker/caller transaction itself; no persistent permissionless DoS mechanism was shown. |
| unsupported_or_speculative | opencode_1 | VirtualToken repayLoan allows arbitrary debt repayment for any user | `repayLoan` is `onlyValidFactory` and burns the target account’s tokens alongside debt reduction; the claimed free external debt manipulation is unsupported. |
| other | opencode_1 | Rebalance infinite approval to OKXTokenApprove | Approvals are set to `amountIn` per call, not to unlimited allowance. |
| unsupported_or_speculative | opencode_1 | Rebalance _executeBuy doesn't validate swap success or returned amount | If execution yields insufficient result, end-of-function profitability checks revert the transaction and roll back state; the claimed permanent loss path was not substantiated. |
| other | opencode_1 | Router getBuyQuote and getSellQuote can return stale/inaccurate quotes | Reserve-based view quotes are inherently point-in-time estimates; this is expected AMM behavior and not a standalone security issue. |
| other | opencode_1 | LamboFactory createLaunchPad does not validate pool creation success | Uniswap V2 `createPair` reverts on failure/existing pair; a meaningful zero-address success path is not realistic under the configured factory. |
| duplicate_or_subsumed | opencode_1 | VirtualToken takeLoan lacks loan repayment tracking per user | This is already captured by existing finding F-002 (global per-block loan quota can be consumed for DoS). |
