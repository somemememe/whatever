# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 13

## Finding Actions
- exact_agent_candidate: 3
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | Self-swaps on the same pool token let attackers ratchet pool prices upward without paying net vCash | codex_1:0.667 Self-swaps are allowed, letting an attacker inflate a pool price without spending vCash |
| F-002 | exact_agent_candidate | High | high | codex_1 | Exact-output swaps undercharge fee-on-transfer `tokenIn` amounts | codex_1:0.984 Exact-output swaps undercharge fee-on-transfer tokenIn amounts |
| F-003 | rewritten_agent_signal | High | high | codex_1 | Anyone can bypass LP withdrawal locks and force-remove another user's liquidity | opencode_1:0.441 Owner Can Pause Pools Without Time Constraint for Some Transitions |
| F-004 | exact_agent_candidate | Medium | low | codex_1 | Only `tokenIn` is locked, so a malicious `tokenOut` can reenter before its pool state is updated | codex_1:0.934 Only `tokenIn` is locked, so a malicious `tokenOut` can reenter before its pool accounting is updated |
| F-005 | exact_agent_candidate | Medium | high | codex_1 | Relisting an unlisted token overwrites its pool id and strands prior LP positions | codex_1:0.933 Relisting an unlisted token overwrites its pool id and can strand old LP positions |

## Rejection Reasons
- duplicate_or_subsumed: 1
- factually_incorrect: 1
- other: 4
- trust_or_owner_model: 7

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | UUPS upgrade authorization is completely unrestricted in `Proxiable` / `ChildOfProxiable` | The code is confined to `contracts/test/Proxiable.sol`, and no production contract in the provided source references or inherits it; this is test-only scaffolding, not a deployed-system issue from the evidence available. |
| trust_or_owner_model | opencode_1 | Owner Can Drain All Pool Funds via Token Status Manipulation | This depends on owner-only privilege changes and existing pool debt; `rebalancePool` only transfers up to the accounted `vcashDebt`/collateralized amount and appears to be an intended privileged recovery path, not a permissionless drain primitive from source alone. |
| trust_or_owner_model | opencode_1 | Missing Zero Address Check for feeTo | This is an owner misconfiguration issue rather than an exploit path; it does not let an attacker steal or lock user funds permissionlessly. |
| trust_or_owner_model | opencode_1 | Excessive Fee Setting Allowed | Bounded fee changes by the owner are governance/centralization risk, not a code vulnerability. |
| factually_incorrect | opencode_1 | Direct Swap Logic Always Returns False | The condition is unusual but not always false: due to integer division it returns true when pool values are within roughly a 2x band, so the claim is factually incorrect. |
| trust_or_owner_model | opencode_1 | Owner Can Arbitrarily Change Pool Prices | This is an explicit owner-only administrative power gated by 6000 blocks of inactivity, so it is a trust/governance concern rather than an unintended vulnerability. |
| trust_or_owner_model | opencode_1 | Missing Access Control on Price Adjuster Role | The owner granting a privileged role is expected governance behavior; no missing access control is shown in the code. |
| duplicate_or_subsumed | opencode_1 | Top LP Removal Restriction Can Be Bypassed | The proposed status-change path is owner-controlled and not the root bug. The reportable issue here is the stronger `msg.sender`/`to` mismatch already captured in F-003. |
| other | opencode_1 | Insufficient Pool Size Validation | The `initialPoolValue <= poolValue \|\| poolValue >= poolSizeMinLimit` check allows trades that increase pool value even if the pool remains below the minimum, which is consistent with preventing further shrinkage rather than proving a harmful bypass. |
| trust_or_owner_model | opencode_1 | Token Insurance Not Backed by Actual Collateral | `tokenInsurance` is an owner-set risk limit, not a collateral vault; the report does not show a concrete exploit beyond governance misrepresentation. |
| trust_or_owner_model | opencode_1 | Owner Can Pause Pools Without Time Constraint for Some Transitions | This is an owner-controlled operational choice and does not itself create realistic protocol-level harm. |
| other | opencode_1 | Rounding Loss in Liquidity Calculations | This is ordinary integer truncation with de minimis effect and not a realistic reportable vulnerability. |
| other | opencode_1 | Uninitialized feeTo Allows Immediate Loss of Fees | `feeTo` being unset is a deployment/configuration issue, not an attacker-triggerable bug; moreover swap fee minting is currently disabled via `_mintFee`. |
