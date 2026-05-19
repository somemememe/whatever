# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 7

## Finding Actions
- exact_agent_candidate: 5

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1,opencode_1 | Pool initialization is permissionless and can be replayed at any time | codex_1:1.0 Pool initialization is permissionless and can be replayed at any time |
| F-002 | exact_agent_candidate | Critical | high | codex_1 | Ambient balance-delta accounting lets anyone steal pending swap or liquidity deposits | codex_1:1.0 Ambient balance-delta accounting lets anyone steal pending swap or liquidity deposits |
| F-003 | exact_agent_candidate | High | high | codex_1 | TWAP oracle is poisonable because cumulative price uses post-update reserves | codex_1:1.0 TWAP oracle is poisonable because cumulative price uses post-update reserves |
| F-004 | exact_agent_candidate | Medium | medium | codex_1 | Fee-tier checks use `tx.origin`, making privileged fee rates transferable and phishable | codex_1:1.0 Fee-tier checks use `tx.origin`, making privileged fee rates transferable and phishable |
| F-006 | exact_agent_candidate | Medium | high | codex_1 | Initial share minting ignores quote-side value, allowing theft of trapped quote balances | codex_1:0.896 Initial share minting ignores quote-side value, allowing theft of quote dust or preloaded quote balances |

## Rejection Reasons
- factually_incorrect: 1
- other: 5
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Swaps and share minting have no on-chain slippage bounds or deadlines | These entrypoints return the achieved output/share amount, so wrappers can enforce min-out or min-share checks atomically by reverting after the call; this is not a standalone core-protocol vulnerability. |
| other | opencode_1 | Flash loan repayment validation uses OR instead of AND | The initial `\|\|` check is followed by per-side deficit checks that require any shortfall on one token to be economically covered by surplus of the other token; simply repaying one side and stealing the other does not pass. |
| other | opencode_1 | Division by zero in pricing calculations when reserves are depleted | Some pricing paths do revert in zero-sided states, but the submitted claim does not establish a permissionless permanent lockup or fund-loss path; the pool can still be rebalanced through liquidity operations. |
| other | opencode_1 | Unchecked token transfer return values in flash loan callback | Outgoing token transfers use `SafeERC20.safeTransfer`, and the callback itself does not transfer tokens; the alleged exploit depends on the rejected flash-loan-underpayment claim. |
| trust_or_owner_model | opencode_1 | Fee rate model owner can set arbitrary fees to extract value | This describes explicit owner/governance authority over the fee model rather than an unintended vulnerability in the pool logic. |
| factually_incorrect | opencode_1 | No slippage protection on flash loan repayment | `flashLoan()` does not execute an external market sale on behalf of the pool; borrowers either return assets or leave surplus collateral, so the slippage framing is incorrect. |
| other | opencode_1 | Permit function lacks deadline protection against front-running | Allowing a permit to be used at exactly its deadline timestamp via `deadline >= block.timestamp` matches standard permit semantics and is not a reportable vulnerability. |
