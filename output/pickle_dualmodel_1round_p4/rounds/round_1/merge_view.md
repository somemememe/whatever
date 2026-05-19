# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 18

## Finding Actions
- exact_agent_candidate: 4
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1,opencode_1,merge_review | `swapExactJarForJar()` trusts attacker-supplied jars and converter calldata, exposing controller-held tokens to theft | codex_1:0.527 Public jar swaps delegatecall user-supplied whitelisted helpers, exposing controller-held tokens to sweep/approval gadgets |
| F-002 | exact_agent_candidate | Medium | high | codex_1,opencode_1 | Permissionless harvests are sandwichable because reward swaps and reinvestment use zero minimums | codex_1:0.927 Permissionless harvests are sandwichable because reward swaps and reinvestment use zero slippage |
| F-003 | exact_agent_candidate | High | high | codex_1,opencode_1 | Public LP conversion contracts expose user principal to MEV because every leg uses zero minimums | codex_1:1.0 Public LP conversion contracts expose user principal to MEV because every leg uses zero minimums |
| F-004 | exact_agent_candidate | Medium | high | codex_1,merge_review | `SCRVVoter.deposit()` is permissionless and can route voter-controlled tokens into an attacker-chosen gauge | codex_1:0.933 `SCRVVoter.deposit` is permissionless and can route voter-controlled assets into attacker-chosen gauges |
| F-005 | exact_agent_candidate | Low | low | codex_1 | The timelock delay can be bypassed for the first admin handoff | codex_1:0.949 The timelock can be bypassed for the first admin handoff |

## Rejection Reasons
- duplicate_or_subsumed: 1
- low_impact_or_operational: 1
- other: 9
- trust_or_owner_model: 5
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Unrestricted Strategic Execution via Delegatecall | `StrategyBase.execute()` is restricted to `timelock` and serves as an explicit privileged emergency hook; this is a trust/governance capability, not a permissionless vulnerability. |
| trust_or_owner_model | opencode_1 | Centralization Risk - Governance Can Change Critical Addresses | This is a generic governance-trust observation rather than a distinct code vulnerability. |
| other | opencode_1 | Deprecated now Keyword Usage | Use of `now`/short deadlines is a style or UX concern here, not a concrete protocol exploit. |
| trust_or_owner_model | opencode_1 | Insufficient Access Control on Keeper Functions | `leverageUntil()` and `deleverageUntil()` are restricted to governance/strategist-approved keepers; the reported risk depends on already trusting a privileged role to whitelist an attacker. |
| other | opencode_1 | Missing Zero Address Validation | This is an admin-misconfiguration concern, not a realistic permissionless exploit. |
| other | opencode_1 | Approval Race Condition | The cited approve-to-zero-then-set pattern is the standard mitigation, not an exploitable race in this context. |
| other | opencode_1 | Unlimited Token Approvals | Approving fixed, well-known protocol routers is an accepted trust assumption here and no contract-specific exploit path was shown. |
| other | opencode_1 | Potential Division Before Multiplication in MasterChef | This is ordinary integer rounding in reward accounting and not a material vulnerability. |
| duplicate_or_subsumed | opencode_1 | OnlyBenevolent Modifier Allows tx.origin | The meaningful security consequence is the public-harvest MEV issue already captured in F-002; `tx.origin` itself is not a separate reportable exploit here. |
| other | opencode_1 | No Pausable Protection on Critical Operations | Allowing withdrawals while paused is typically an intentional emergency design choice, not a vulnerability. |
| unsupported_or_speculative | opencode_1 | Missing Reentrancy Protection in PickleJar Withdraw | `PickleJar.withdraw()` burns shares before transferring assets, so the claimed stale-state reentrancy path is unsupported. |
| other | opencode_1 | Timelock Execute Allows Arbitrary Value Transfer | This is the intended behavior of a timelock-admin executor and not a permissionless bug. |
| trust_or_owner_model | opencode_1 | CRVLocker Execute Allows Arbitrary Calls | `CRVLocker.execute()` is limited to approved voters or governance; this is a privileged-role trust assumption. |
| other | opencode_1 | SCRVVoter Allows Strategy to Execute Arbitrary Calls | Approved strategies are trusted actors by design; the actual reportable issue is the missing authorization on `SCRVVoter.deposit()`, captured in F-004. |
| unsupported_or_speculative | opencode_1 | Unsafe Casting in Strategy Curve 3CRV | `getMostPremium()` only returns indices 0, 1, or 2, so the claimed out-of-bounds array access is not supported by the code. |
| low_impact_or_operational | opencode_1 | Hardcoded Gas Stipend May Cause Execution Failure | `delegatecall(sub(gas(), 5000), ...)` forwards nearly all remaining gas to the callee; it does not cap the callee at 5000 gas. |
| trust_or_owner_model | opencode_1 | MasterChef Dev Fund Rate Can Be Set to Any Value | This is an owner/governance policy choice rather than a permissionless contract flaw. |
| other | opencode_1 | PickleJar Ratio Manipulation Via Deposit Order | The cited deposit share accounting follows standard vault math and the proposed sandwich theft path is not substantiated by the implementation. |
