# Merge View - Round 1

## Summary
- total findings: 2
- new findings: 2
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Anyone can burn arbitrary users' tokens via the inverted allowance check in burnFrom | codex_1:1.0 Anyone can burn arbitrary users' tokens via the inverted allowance check in burnFrom |
| F-002 | rewritten_agent_signal | High | medium | codex_1,merge_review | Upgrade leaves the hidden legacy ledger live through non-deprecated write paths | codex_1:0.491 The upgrade switch leaves legacy balances and allowances spendable through bulk transfer helpers |

## Rejection Reasons
- other: 6
- trust_or_owner_model: 1
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Owner can steal all ERC20 tokens in the contract via acquire() | `acquire()` only withdraws assets already held by the token contract itself; the contract has no deposit accounting, so this is a stray-asset recovery/admin-trust behavior rather than a vulnerability affecting tracked user balances. |
| other | opencode_1 | Blacklisted users can still burn their tokens | Allowing a blacklisted holder to destroy their own tokens does not let them transfer value or bypass the freeze in a way that creates realistic protocol harm. |
| trust_or_owner_model | opencode_1,codex_1 | Upgrade can irreversibly redirect all token operations to malicious contract | Pointing upgrades at a malicious target is an owner-trust/centralization risk, not a permissionless bug; additionally, `upgrade()` is not irreversible because the owner can call it again and change `upgradedAddress`. |
| other | opencode_1 | Bulk transfer functions bypass blacklist checks | False positive: both bulk transfer variants eventually call `_transfer` and `_allowanceTransfer`, which enforce blacklist and pause checks. |
| other | opencode_1 | Critical owner functions remain operational during pause | The pause modifier is consistently applied to token-movement paths; administrative functions remaining callable is a design choice, not an exploitable protocol vulnerability by itself. |
| unsupported_or_speculative | opencode_1 | Immutable DOMAIN_SEPARATOR breaks permit on chain forks | This is a speculative fork-compatibility concern rather than a realistic in-scope vulnerability causing present protocol harm. |
| other | opencode_1 | Missing event emissions for role management | This is a monitoring/transparency issue only and does not create direct protocol-level harm. |
| other | opencode_1 | acquire() allows stealing ETH from contract | Same root issue as the ERC20 `acquire()` candidate: it only recovers ETH held by the contract itself, with no user accounting or payable deposit flow to violate. |
