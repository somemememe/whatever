# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 7

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | Swap invariant uses a 10,000-based fee adjustment against a 1,000-based RHS, allowing near-total reserve drainage | codex_1:0.617 Swap invariant is scaled 100x too low, enabling near-total reserve drainage |
| F-002 | exact_agent_candidate | High | high | codex_1 | Swaps are hard-coupled to an external referral contract, creating a single-point denial of service | codex_1:0.86 Every swap is hard-coupled to an external referral contract, creating a single-point DOS |
| F-003 | exact_agent_candidate | Medium | high | codex_1 | Factory can reinitialize an existing pair because initialization is not one-time | codex_1:1.0 Factory can reinitialize an existing pair because initialization is not one-time |
| F-004 | rewritten_agent_signal | Low | high | codex_1,opencode_1 | Any LP tokens held by the pair are permissionlessly redeemable, including misrouted protocol fees | codex_1:0.497 Any LP tokens sent to the pair contract can be burned and redeemed by anyone |

## Rejection Reasons
- other: 6
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Flash loan attack via callback + skim allows stealing pool funds | `swap()` and `skim()` share the same `lock` modifier, so `skim()` cannot be reentered from `NimbusCall`; the proposed exploit path is blocked. |
| unsupported_or_speculative | opencode_1 | DOMAIN_SEPARATOR not updated on chain fork leading to signature reuse | The code matches an older fixed-domain permit pattern, but the risk is fork-contingent and too speculative for a reportable issue in this audit. |
| other | opencode_1 | Swap callback allows arbitrary external calls enabling potential attack vectors | This is the standard flash-swap callback pattern; no concrete exploit survives the pair's reentrancy lock. |
| other | opencode_1 | Hardcoded magic number for infinite approval | Readability issue only; not a security vulnerability. |
| other | opencode_1 | No check for zero-address in setFeeTo | `setFeeTo` is not implemented in this contract, and a zero `feeTo` is the normal way to disable fees. |
| other | opencode_1 | Missing sync before K check | The invariant check uses live token balances read immediately before validation, so a prior `sync()` is unnecessary. |
| other | codex_1 | Anyone can steal tokens accidentally sent to the pair via skim | `skim()` is an intentional Uniswap-style dust recovery mechanism that only transfers balances above recorded reserves; this is by design rather than a distinct vulnerability. |
