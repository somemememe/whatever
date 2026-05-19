# Merge View - Round 7

## Summary
- total findings: 17
- new findings: 2
- updated existing findings: 15
- rejected candidates: 2

## Finding Actions
- exact_agent_candidate: 1
- existing_rewritten: 15
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | existing_rewritten | High | high | codex_1,opencode_1 | VirtualToken.cashIn mints by msg.value for ERC20 underlyings, enabling unbacked minting/mis-accounting | codex_1:0.295 Caller-controlled rebalance mask is passed into the external swap descriptor unsanitized |
| F-002 | existing_rewritten | Medium | high | codex_1 | Permissionless createLaunchPad can consume per-block vETH loan quota and DoS other launches | codex_1:0.344 Router fee can be raised to 100% and confiscate zero-minimum sells |
| F-003 | existing_rewritten | High | high | codex_1 | Router sell pricing uses full vETH reserves including debt-locked liquidity, causing sell reverts and exit lockups | codex_1:0.344 Router fee can be raised to 100% and confiscate zero-minimum sells |
| F-004 | existing_rewritten | Low | high | codex_1,opencode_1 | buyQuote refund logic withholds 1 wei from overpayments | codex_1:0.248 Any valid factory can burn debt balances from any borrower |
| F-005 | existing_rewritten | Medium | low | codex_1 | Rebalance initialization can be seized if deployment is non-atomic or proxy is left uninitialized | codex_1:0.405 Rebalance preview can be unusable against non-view V3 quoters |
| F-006 | existing_rewritten | Critical | high | codex_1 | Launchpad creation reverts because factory transfers LP tokens to the zero address | codex_1:0.338 Router fee can be raised to 100% and confiscate zero-minimum sells |
| F-007 | existing_rewritten | High | high | codex_1 | Predictable clone address enables pair pre-creation that can indefinitely brick targeted launch attempts | codex_1:0.302 Caller-controlled rebalance mask is passed into the external swap descriptor unsanitized |
| F-008 | existing_rewritten | Low | high | codex_1,opencode_1 | Rebalance ignores caller-provided output target and executes swaps with zero minimum return | codex_1:0.471 Router fee can be raised to 100% and confiscate zero-minimum sells |
| F-009 | existing_rewritten | Low | medium | codex_1 | Router and rebalance flows never enforce that configured vETH is native-backed, enabling full functional DoS via misconfiguration | codex_1:0.35 Caller-controlled rebalance mask is passed into the external swap descriptor unsanitized |
| F-010 | existing_rewritten | Low | medium | codex_1 | previewRebalance uses raw pool token balances, allowing donation-based signal manipulation | codex_1:0.384 Rebalance preview can be unusable against non-view V3 quoters |
| F-011 | existing_rewritten | Medium | high | codex_1 | Router fees are bypassable through direct trading against the public launch pair | codex_1:0.342 Router fee can be raised to 100% and confiscate zero-minimum sells |
| F-012 | existing_rewritten | Medium | medium | codex_1,opencode_1 | Rebalance swap direction and caller-supplied pool mask are not validated against pool token order | codex_1:0.418 Rebalance preview can be unusable against non-view V3 quoters |
| F-013 | existing_rewritten | Medium | medium | codex_1 | Uniswap V2 fee switch can mint LP shares despite the intended burned-liquidity model | codex_1:0.296 Any valid factory can burn debt balances from any borrower |
| F-014 | existing_rewritten | Low | medium | codex_1 | Whitelisted router can be used as a generic arbitrary-pair vETH redemption adapter | codex_1:0.365 Router fee can be raised to 100% and confiscate zero-minimum sells |
| F-015 | existing_rewritten | Low | high | codex_1 | Native ETH accepted by router and rebalancer has no recovery path | codex_1:0.439 Any valid factory can burn debt balances from any borrower |
| F-016 | exact_agent_candidate | Low | medium | codex_1 | Rebalance preview can be unusable against non-view V3 quoters | codex_1:1.0 Rebalance preview can be unusable against non-view V3 quoters |
| F-017 | rewritten_agent_signal | Medium | medium | codex_1 | Valid factories can repay and burn debt for arbitrary borrowers, allowing cross-factory launch-pair reserve corruption | codex_1:0.466 Any valid factory can burn debt balances from any borrower |

## Rejection Reasons
- duplicate_or_subsumed: 1
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex_1 | Router fee can be raised to 100% and confiscate zero-minimum sells | Not kept as a reportable vulnerability because the fee change is an explicit onlyOwner parameter, the confiscation scenario requires a trusted owner or compromised owner plus user/integration minReturn=0, and nonzero minReturn sells revert rather than settle at zero. |
| duplicate_or_subsumed | codex_1 | Caller-controlled rebalance mask is passed into the external swap descriptor unsanitized | Not kept as a separate finding. The supported part overlaps with F-012's mask/order validation issue and was folded there; the standalone claim about extra OKX descriptor bits causing loss remains speculative without a concrete router-semantics or fund-loss path, and failed rebalances revert. |
