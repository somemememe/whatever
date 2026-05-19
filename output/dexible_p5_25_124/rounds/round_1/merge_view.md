# Merge View - Round 1

## Summary
- total findings: 2
- new findings: 2
- updated existing findings: 0
- rejected candidates: 13

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Permissionless `selfSwap()` lets anyone execute arbitrary external calls as Dexible and steal approved user funds | codex_1:0.485 Public `selfSwap()` can recurse into `fill()` and steal from arbitrary approved users |
| F-002 | exact_agent_candidate | High | medium | codex_1,opencode_1 | Proxy deployment can be left uninitialized, allowing first caller to seize admin and upgrade control | codex_1:1.0 Proxy deployment can be left uninitialized, allowing first caller to seize admin and upgrade control |

## Rejection Reasons
- duplicate_or_subsumed: 3
- low_impact_or_operational: 1
- other: 7
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Public `selfSwap()` can recurse into `fill()` and steal from arbitrary approved users | Accepted in stronger form as F-001. The core issue is broader: `selfSwap()` already exposes arbitrary external calls from Dexible, so attackers can directly invoke `token.transferFrom(...)` without needing nested `fill()` recursion. |
| duplicate_or_subsumed | codex_1 | Arbitrary route calls expose Dexible-only vault hooks such as `rewardTrader()` | Subsumed by F-001’s broader arbitrary-call finding. Vault-hook abuse is a plausible extension, but the snapshot only includes vault interfaces/storage comments, so the vault-specific impact is less directly provable than the token-theft primitive. |
| duplicate_or_subsumed | codex_1 | Only `routes[0]` is funded and bounded, so later routes can steal Dexible-held ERC20 balances | Subsumed by F-001. Attackers can directly call ERC20 `transfer`/`transferFrom` from Dexible via any route, so theft does not depend on later routes or the `routes[0]` accounting bug. |
| unsupported_or_speculative | opencode_1 | Reentrancy vulnerability in swap and fee distribution | Not supported as an independent reportable issue. The dangerous behavior comes from the explicit arbitrary external-call design, not from a demonstrated reentrancy-sensitive state invariant. |
| duplicate_or_subsumed | opencode_1 | Unlimited token approval to arbitrary routers | Incorrect as stated: approvals are per-route amounts, not unlimited. Concrete abuse from arbitrary route execution is already captured in F-001. |
| other | opencode_1 | Affiliate address not validated - fees can be redirected | Not a protocol-auth bypass. Affiliate payment follows caller/relay-supplied execution metadata; redirecting it is part of the submitted request rather than an unintended privilege escalation. |
| other | opencode_1 | Missing zero-address validation on critical setters | Admin-only misconfiguration risk, not a permissionless or realistic adversarial protocol exploit. |
| other | opencode_1 | Potential integer overflow in gas cost calculation | Solidity 0.8.17 uses checked arithmetic by default, so overflow would revert rather than silently miscompute fees. |
| low_impact_or_operational | opencode_1 | Hardcoded Optimism gas oracle address | Operational/maintainability concern, not a security finding with realistic protocol-level harm in this snapshot. |
| unsupported_or_speculative | opencode_1 | Missing event emissions for configuration changes | Non-security issue and not supported by a protocol-harmful exploit path. |
| other | opencode_1 | Use of deprecated transfer methods for ETH | Low-impact compatibility issue affecting admin withdrawal or relay reimbursement only; it does not create realistic fund-theft, insolvency, or permissionless DoS risk here. |
| other | opencode_1 | Proxy implementation can be upgraded without timelock confirmation | Not a vulnerability. Upgrades are still gated by the existing timelock and admin proposal flow; public execution after the timelock is an intended pattern. |
| other | opencode_1 | Implementation contract initialization not protected | Directly initializing the standalone implementation affects the implementation’s own storage, not the proxy’s live state, so it does not by itself seize control of the deployed protocol. |
