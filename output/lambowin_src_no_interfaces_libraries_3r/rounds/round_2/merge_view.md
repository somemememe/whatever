# Merge View - Round 2

## Summary
- total findings: 6
- new findings: 1
- updated existing findings: 1
- rejected candidates: 13

## Finding Actions
- existing_preserved: 4
- existing_support_added: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | existing_support_added | High | high | codex_1,opencode_1 | VirtualToken.cashIn mints by msg.value for ERC20 underlyings, enabling unbacked minting/mis-accounting | opencode_1:0.644 VirtualToken cashIn for ERC20 underlyings uses msg.value for minting amount |
| F-006 | rewritten_agent_signal | Critical | high | codex_1 | Launchpad creation reverts because factory transfers LP tokens to the zero address | codex_1:0.691 Launchpad creation can revert permanently when burning LP tokens to zero address |

## Rejection Reasons
- duplicate_or_subsumed: 2
- factually_incorrect: 2
- low_impact_or_operational: 1
- other: 7
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex_1 | Virtual debt is created but has no practical settlement path in launch flow | Mostly overlaps with F-003’s debt-locked-liquidity root cause/impact; presented path is design-level and not a clearly separate exploit primitive. |
| other | codex_1,opencode_1 | Rebalance executes permissionless flash-loan trades with no enforced output bound | Swaps are atomic with the flash-loan transaction and `rebalance` enforces post-trade profitability (`profit > 0`) or reverts, so no demonstrated protocol fund-loss path from public callers. |
| other | codex_1 | Public token initializer allows first-caller ownership of any uninitialized instance supply | Factory deployment path initializes clones atomically in the same transaction; no practical front-run window in normal protocol flow. |
| low_impact_or_operational | codex_1 | Hardcoded infrastructure addresses without chain guard create unsafe deployment assumptions | Operational/deployment-configuration risk rather than an in-protocol exploitable vulnerability. |
| factually_incorrect | opencode_1 | Router _sellQuote executes swap before fee calculation, enabling front-running fee extraction | Incorrect: if later checks fail, the entire transaction reverts, including the swap; no partial execution value loss is left on-chain. |
| other | opencode_1 | VirtualToken _update allows transferring tokens without considering incoming transfers for debt position | Debt-floor enforcement on sender is intentional; receiving tokens without auto-repay is by design and does not bypass debt-transfer restrictions. |
| duplicate_or_subsumed | opencode_1 | VirtualToken cashIn for ERC20 underlyings uses msg.value for minting amount | Duplicate of F-001. |
| other | opencode_1 | Router lacks deadline parameter allowing stale execution | Best-practice gap, but `minReturn` already provides execution-price protection; no distinct exploit demonstrated. |
| other | opencode_1 | LamboFactory createLaunchPad has no verification of pool creation success | For Uniswap V2 factory semantics, `createPair` reverts on failure and returns a deployed pair on success; `address(0)` success path is not realistic. |
| other | opencode_1 | VirtualToken has no pause mechanism for emergency response | Absence of a pause feature alone is not a vulnerability. |
| factually_incorrect | opencode_1 | Router getBuyQuote and getSellQuote don't account for fee in amountOut calculation | Incorrect: `getSellQuote` and `_sellQuote` both compute AMM output then deduct fee from output consistently. |
| other | opencode_1 | Rebalance directionMask accepts any uint256 allowing pool address manipulation | Arbitrary masks can make caller-supplied rebalance attempts revert, but do not create a protocol-level exploit or permissionless fund-loss path. |
| trust_or_owner_model | opencode_1 | Router fee rate can be set to 100% causing total user funds loss | Privileged-owner parameterization/trust-model concern, not a permissionless vulnerability. |
