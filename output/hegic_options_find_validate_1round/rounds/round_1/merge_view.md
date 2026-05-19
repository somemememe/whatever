# Merge View - Round 1

## Summary
- total findings: 17
- new findings: 3
- updated existing findings: 1
- rejected candidates: 1

## Finding Actions
- existing_preserved: 13
- existing_rewritten: 1
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-004 | existing_rewritten | High | medium | codex | Chainlink oracle reads are used without freshness or round-validity checks | codex:0.32 Core accounting assumes exact ERC20 transfers, enabling reserve inflation with fee-on-transfer tokens |
| F-201 | rewritten_agent_signal | Medium | medium | codex,merge-review | Reserve accounting assumes exact ERC20 transfers, enabling short-transfer undercollateralization and reserve drains | codex:0.648 Core accounting assumes exact ERC20 transfers, enabling reserve inflation with fee-on-transfer tokens |
| F-202 | rewritten_agent_signal | Medium | medium | codex,merge-review | PriceCalculatorUtilization uses raw option size instead of put collateral, mispricing put-pool utilization | codex:0.551 PriceCalculatorUtilization materially underestimates put-pool utilization and undercharges large puts |
| F-203 | rewritten_agent_signal | Low | medium | codex,merge-review | AdaptivePutPriceCalculator hardcodes quote-token and oracle decimals, creating silent mispricing on non-standard deployments | codex:0.521 AdaptivePutPriceCalculator silently assumes 6-decimal quote tokens and 8-decimal oracle answers |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | Dust call options can be minted for zero premium and zero collateral | Supported by rounding, but the extractable value is negligible and mainly causes low-grade state bloat; it does not create realistic protocol-level fund loss, theft, insolvency, permanent lockup, or meaningful DoS. |
