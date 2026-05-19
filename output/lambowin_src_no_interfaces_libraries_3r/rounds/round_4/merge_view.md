# Merge View - Round 4

## Summary
- total findings: 10
- new findings: 2
- updated existing findings: 2
- rejected candidates: 11

## Finding Actions
- exact_agent_candidate: 1
- existing_preserved: 6
- existing_rewritten: 1
- existing_support_added: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-004 | existing_support_added | Low | high | codex_1,opencode_1 | buyQuote refund logic withholds 1 wei from overpayments | opencode_1:0.459 Router buyQuote allows overpayment without full refund |
| F-008 | existing_rewritten | Low | high | codex_1,opencode_1 | Rebalance ignores caller-provided output target and executes swaps with zero minimum return | opencode_1:0.638 LamboRebalanceOnUniwap executes swaps with hardcoded zero minimum return |
| F-009 | rewritten_agent_signal | Low | medium | codex_1 | Router and rebalance flows never enforce that configured vETH is native-backed, enabling full functional DoS via misconfiguration | codex_1:0.381 Router and rebalance flows assume ETH-backed vToken semantics without enforcement |
| F-010 | exact_agent_candidate | Low | medium | codex_1 | previewRebalance uses raw pool token balances, allowing donation-based signal manipulation | codex_1:0.937 previewRebalance uses raw token balances, enabling donation-based signal manipulation |

## Rejection Reasons
- factually_incorrect: 2
- other: 9

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Hardcoded dependency addresses without chain/code validation can cause catastrophic misdeployment loss | Mainnet-specific constants are explicit (e.g., `ETH Mainnet` comments); this is primarily deployment-configuration risk rather than a permissionless in-protocol exploit. |
| other | codex_1 | Rebalance directionMask is not validated and can corrupt encoded pool routing bits | Malformed `directionMask` is caller-controlled in a public function and mainly self-inflicts revert paths; no concrete theft or third-party DoS path was established. |
| other | codex_1 | VirtualToken.takeLoan is payable and can trap ETH with no dedicated recovery path | Only trusted `validFactories` can call `takeLoan`; current in-scope factory flow does not forward ETH, so no realistic permissionless exploit was shown. |
| other | codex_1 | Unrestricted quoteToken routing turns whitelisted router into a generic vETH cash-out bridge | Routing arbitrary vETH pairs appears intentional router behavior; no demonstrated drain or whitelist bypass beyond normal AMM trading was substantiated. |
| factually_incorrect | opencode_1 | VirtualToken.cashOut burns tokens before sending underlying assets | Incorrect: if underlying transfer fails, the transaction reverts atomically and the prior burn is rolled back. |
| other | opencode_1 | LamboRebalanceOnUniwap executes swaps with hardcoded zero minimum return | Merged into existing F-008 (same root cause: `minReturn=0` and missing slippage floor). |
| other | opencode_1 | Rebalance lacks slippage protection on caller-provided amountOut | Merged into existing F-008 (same root cause: `amountOut` ignored and no enforced minimum output). |
| factually_incorrect | opencode_1 | VirtualToken.repayLoan can burn tokens without corresponding debt reduction | Incorrect: function is `onlyValidFactory`, and `_decreaseDebt` must pass before burn, preventing debt/accounting mismatch claims. |
| other | opencode_1 | Rebalance onMorphoFlashLoan lacks validation on pool parameter | Pool address is initialized state, not user-provided per call; candidate did not demonstrate a practical permissionless exploit path. |
| other | opencode_1 | Router buyQuote allows overpayment without full refund | Merged into existing F-004 (same 1-wei refund shortfall). |
| other | opencode_1 | Rebalance extractProfit can drain flash loaned funds | Not feasible in stated form: `extractProfit` cannot interleave inside the same flash-loan execution; any failed repayment would revert atomically. |
