# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 5

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | Pool-directed transferFrom can burn more tokens than the approved allowance | codex_1:0.966 Pool-directed transferFrom burns more tokens than the approved allowance |
| F-002 | rewritten_agent_signal | Medium | high | codex_1 | Pool-directed transfers charge the burn on top of `amount`, causing exact-balance sells and exact-amount integrations to revert | codex_1:0.442 Sell transfers require extra balance beyond the requested amount and can revert exact-balance exits |
| F-003 | exact_agent_candidate | Low | high | codex_1 | Sell-path Transfer events do not match actual balance changes | codex_1:0.865 Sell-path Transfer events are fabricated and do not match actual balance changes |
| F-004 | rewritten_agent_signal | Medium | medium | codex_1,opencode_1 | Owner can retarget the broken sell-path logic to any arbitrary destination address | codex_1:0.786 Owner can retarget the punitive pool logic to any arbitrary destination address at any time |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 2
- trust_or_owner_model: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Owner can arbitrarily set pool address enabling fund theft | The code does let the owner retarget the special transfer path, but it does not call external contracts during transfer, so the claimed malicious callback/reentrancy theft path is unsupported. This is better framed as owner-retargetable griefing/integration breakage, which is captured in F-004. |
| other | opencode_1 | Owner can arbitrarily redirect marketing fee to any address | `marketingWalletAddress` is never credited in storage. On sell-path transfers the contract only emits a synthetic `Transfer` event to that address, so changing it does not redirect actual token balances or create a real fee-theft vector. |
| trust_or_owner_model | opencode_1 | No timelock on critical administrative functions | Lack of a timelock is a governance/centralization concern, not a standalone vulnerability here. The reportable issue is the underlying owner-retargetable broken transfer logic, not the absence of a delay mechanism. |
| other | opencode_1 | Missing events for critical parameter changes | This is a transparency issue only. It does not by itself cause realistic fund loss, lockup, insolvency, economic manipulation, or protocol-level DoS. |
| duplicate_or_subsumed | opencode_1 | High owner concentration - single point of failure | Generic centralization risk without a distinct exploit path beyond the specific owner-controlled behavior already captured in F-004. |
