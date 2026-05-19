# Merge View - Round 5

## Summary
- total findings: 13
- new findings: 3
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 10
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-011 | rewritten_agent_signal | Medium | high | codex_1 | Router fees are bypassable through direct trading against the public launch pair | codex_1:0.69 Router fees are bypassable through direct Uniswap pair trading |
| F-012 | rewritten_agent_signal | Medium | medium | codex_1,opencode_1 | Rebalance swap direction is encoded from WETH identity instead of the pool token order | codex_1:0.649 Rebalance swap direction assumes a fixed WETH/vETH token ordering |
| F-013 | exact_agent_candidate | Medium | medium | codex_1 | Uniswap V2 fee switch can mint LP shares despite the intended burned-liquidity model | codex_1:0.924 Uniswap V2 fee switch can mint LP shares despite intended burned liquidity |

## Rejection Reasons
- duplicate_or_subsumed: 4
- other: 8

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | Native ETH sent to router or rebalance can become permanently stuck | Only accidental or forced direct ETH transfers are shown. Normal router-created dust is already captured by F-004, and the rebalance contract wraps ETH produced during its buy path; no permissionless third-party protocol fund lockup is demonstrated. |
| other | codex_1 | LamboToken implementation can be initialized by anyone | Factory-created clones use separate storage and are initialized atomically. Initializing the template only creates a misleading standalone ERC20 at the implementation address, which is an off-chain confusion/phishing risk rather than protocol-level asset loss. |
| other | codex_1 | previewRebalance reverts instead of returning no-op when pool balances are equal | A balanced-pool preview revert is an integration/keeper UX issue. It does not move funds, block a needed profitable rebalance, or create realistic protocol-level harm. |
| other | opencode_1 | Rebalance directionMask validation bypass allows wrong swap direction | The invalid-mask claim alone is not independently exploitable: arbitrary callers can only make their own rebalance transaction revert or fail the final WETH profit check. The supported pool-order/mask-validation aspect is merged into F-012. |
| duplicate_or_subsumed | opencode_1 | Rebalance amountOut parameter completely ignored by execution | Duplicate of F-008; the existing finding already covers the unused `amountOut` parameter. |
| other | opencode_1 | VirtualToken cashOut burns tokens before verifying backed collateral | If `_transferAssetToUser` fails, the transaction reverts and the preceding `_burn` is reverted as well, so failed collateral transfer does not permanently burn user tokens. |
| other | opencode_1 | VirtualToken repayLoan allows arbitrary third-party debt repayment | `repayLoan` is restricted to `validFactories`, and the in-scope factory exposes no caller-controlled repay path. The candidate depends on trusted/admin misconfiguration rather than a permissionless exploit path. |
| other | opencode_1 | getSellQuote uses flash-loan-manipulable reserves | `getSellQuote` is a view over standard AMM reserves, and `_sellQuote` executes against current reserves with caller-supplied `minReturn`; no protocol value extraction beyond normal AMM price/slippage behavior is shown. |
| duplicate_or_subsumed | opencode_1 | Rebalance OKXRouter swaps use zero minimum return | Duplicate of F-008; the existing finding already covers zero-minimum-return rebalance swaps. |
| other | opencode_1 | VirtualToken takeLoan lacks atomicity against concurrent calls | EVM transactions execute serially; the quota check and `loanedAmountThisBlock` increment are atomic within a transaction, so two calls cannot both pass using stale state. |
| duplicate_or_subsumed | opencode_1 | LamboFactory createLaunchPad has no deadline, vulnerable to front-running | A missing deadline is not by itself a protocol exploit for this function. Concrete launch front-running/DoS vectors are already captured by F-002 and F-007. |
| other | opencode_1 | VirtualToken isValidFactory returns true without verification | The function intentionally exposes the `validFactories` mapping. The candidate does not show a stale-read, authorization bypass, or other harmful path supported by the code. |
