# Merge View - Round 1

## Summary
- total findings: 7
- new findings: 7
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- exact_agent_candidate: 4
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | Privileged wallets receive all LP tokens and can withdraw pooled liquidity | codex_1:0.937 Privileged wallets receive all LP tokens and can rug pooled liquidity |
| F-002 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Reward-cap enforcement is broken, allowing over-minting past `maxSupply` and stranding later stakers | codex_1:0.593 Broken reward-cap enforcement lets one staker overmint and strand everyone else's rewards |
| F-003 | exact_agent_candidate | High | high | codex_1 | Owner or fee receiver can erase all pending staking yield by disabling staking | codex_1:0.943 Owner or fee receiver can zero out all pending staking yield by disabling staking |
| F-004 | rewritten_agent_signal | Medium | high | codex_1 | Previous operator keeps team-level powers after ownership transfer or renounce | codex_1:0.361 Ownership transfer or renounce does not revoke the previous operator's team-level powers |
| F-005 | rewritten_agent_signal | Medium | medium | opencode_1 | Setting fees to zero bricks taxed AMM transfers through division by zero | opencode_1:0.404 Zero denominator in SafeMath division |
| F-006 | exact_agent_candidate | Medium | medium | codex_1,opencode_1 | Zero-slippage fee swaps are sandwichable and leak fee value to MEV | codex_1:0.899 Zero-slippage fee swaps are sandwichable and leak value to MEV searchers |
| F-007 | exact_agent_candidate | Low | high | codex_1,opencode_1 | `userEarned()` mixes the queried account with `msg.sender`'s cached rewards | codex_1:0.973 userEarned() mixes the queried account with msg.sender's cached rewards |

## Rejection Reasons
- other: 7
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | No validation on APR allows extremely high reward rates | `apr` is fixed to 50 in the constructor and this contract exposes no setter, so there is no reachable path to arbitrarily raise APR. |
| other | opencode_1 | Zero denominator in SafeMath division | The library's `div` helper does check `b > 0` with `require`; the issue is not the library itself but the separate fee-math misconfiguration captured in F-005. |
| other | opencode_1 | Incorrect reward calculation - division by 1 seconds is ineffective | The `1 seconds` divisions are redundant but harmless, and the reward formula's integer truncation does not by itself create a realistic protocol-level exploit. |
| other | opencode_1 | Unlimited token approval to Uniswap router | Approving the canonical Uniswap V2 router for contract-held tokens is standard and does not constitute a standalone vulnerability here. |
| other | opencode_1 | Bot protection bypass using tx.origin | Using `tx.origin` is poor design, but the proposed front-running bypass is not substantiated and does not show a concrete exploitable failure beyond weak anti-bot heuristics. |
| other | opencode_1 | Missing zero address validation in stake/unstake | There is no address parameter in `stake()`/`unstake()`, zero-amount stakes do not create a realistic exploit, and invalid validator indices revert on array bounds checks rather than corrupting state. |
| trust_or_owner_model | opencode_1 | No validation on fee receiver address | Allowing the privileged controller to set `_swapFeeReceiver` to `address(0)` is a self-inflicted configuration hazard, not a permissionless vulnerability. |
| other | opencode_1 | Validator index not validated in multiple functions | Out-of-range validator indices revert automatically on Solidity array bounds checks; this is not a separate reportable issue. |
