# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 7

## Finding Actions
- exact_agent_candidate: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Swap invariant is weakened by a 100x scaling mismatch, allowing near-total reserve drains | codex_1:1.0 Swap invariant is weakened by a 100x scaling mismatch, allowing near-total reserve drains |
| F-002 | exact_agent_candidate | High | high | codex_1 | Referral fee transfers are excluded from reserve accounting, corrupting reserves after swaps | codex_1:0.963 Referral fee transfers are excluded from reserve accounting, corrupting reserves after every swap |
| F-003 | exact_agent_candidate | Medium | low | codex_1 | Referral rewards are attributed to a caller-controlled `to` address, enabling likely self-referral farming | codex_1:0.953 Referral rewards are attributed to the user-controlled `to` address, enabling likely self-referral farming |

## Rejection Reasons
- factually_incorrect: 1
- other: 6

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Reentrancy via callback before K invariant validation | `swap()` is protected by the `lock` modifier, so reentrant calls into the pair's state-changing entrypoints revert. Calling `NimbusCall` before the invariant check is the standard flash-swap pattern and is not by itself an exploitable reentrancy bug here. |
| factually_incorrect | opencode_1 | Unvalidated referral program can steal user funds | The referral program address is a trusted factory-controlled dependency, not a permissionless attack surface. Also, receiving ERC20 transfers does not invoke a recipient fallback, so the stated fallback-based theft path is incorrect. |
| other | opencode_1 | Arbitrary external call enables flash loan attacks | Allowing a callback to `to` is the normal flash-swap mechanism for Uniswap V2-style pairs, not a standalone vulnerability. Profitability still depends on external market conditions, not a flaw in this contract. |
| other | opencode_1 | Referral fees transferred before K validation | If the later `require` fails, the whole transaction reverts, including the ERC20 transfers and `recordFee()` call. The fees are not permanently lost on a reverted swap. |
| other | opencode_1 | No slippage protection allows unlimited slippage | This pair is a low-level AMM primitive. Slippage protection is normally enforced by routers or callers, so the absence of min-out parameters in the pair itself is not reportable. |
| other | opencode_1 | Permissionless skim and sync functions | These functions are standard for Uniswap V2-style pairs. `skim()` only transfers excess balances above reserves, and `sync()` only aligns reserves to actual balances; neither creates a realistic standalone exploit here. |
| other | opencode_1 | Unusual referral fee denominator | Using `1994` is unusual but plausibly intentional to approximate a 0.15% referral charge. On its own this is not evidence of an exploitable bug or meaningful protocol harm. |
