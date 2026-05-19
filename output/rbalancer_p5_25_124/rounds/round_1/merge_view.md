# Merge View - Round 1

## Summary
- total findings: 7
- new findings: 7
- updated existing findings: 0
- rejected candidates: 11

## Finding Actions
- exact_agent_candidate: 5
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | Instant withdrawals can burn full shares but return only a fraction of the owed ETH | codex_1:1.0 Instant withdrawals can burn full shares but return only a fraction of the owed ETH |
| F-002 | exact_agent_candidate | High | medium | codex_1 | First depositor can capture any ETH already sitting in the system before round 1 starts | codex_1:0.948 First depositor can capture any ETH already sitting in the vault before round 1 starts |
| F-003 | exact_agent_candidate | High | high | codex_1 | Remote bridge pause, cap, and price-feed messages always fail because STONE never handles its custom packet types | codex_1:1.0 Remote bridge pause, cap, and price-feed messages always fail because Stone never handles its custom packet types |
| F-004 | rewritten_agent_signal | High | medium | codex_1 | A small instant withdraw can steal all ETH already stranded in StrategyController | codex_1:0.582 A withdrawer can receive all ETH stranded in StrategyController even when they only requested a small amount |
| F-005 | exact_agent_candidate | Medium | medium | codex_1 | Post-settlement insolvency makes share-price math underflow and blocks recapitalization flows | codex_1:0.979 Any post-settlement insolvency makes share-price math underflow and blocks recapitalization flows |
| F-006 | rewritten_agent_signal | Medium | medium | codex_1 | rollToNextRound is reentrant through strategy callbacks before round state is updated | codex_1:0.728 rollToNextRound is reentrant through strategy callbacks and updates round accounting only after external calls |
| F-007 | exact_agent_candidate | Low | high | codex_1,opencode_1 | Unvalidated strategy addresses can permanently brick pricing and rebalancing | codex_1:1.0 Unvalidated strategy addresses can permanently brick pricing and rebalancing |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 5
- trust_or_owner_model: 4
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | opencode_1 | Share Price Calculation Error Causes User Fund Loss in instantWithdraw | `instantWithdraw()` using the lower of current and last-settled price is a conservative pricing rule, not a standalone exploit. The real reportable issue is the separate burn-before-liquidity-check bug already captured in F-001. |
| other | opencode_1 | Fee Not Applied to Share-Based Withdrawals | False positive. The withdrawal fee is applied to `actualWithdrawn` after both the amount-based and share-based branches, so share-based instant withdrawals do pay fees. |
| unsupported_or_speculative | opencode_1 | Lack of Slippage Protection in Rebalancing | Too speculative and strategy-dependent. The controller just routes deposits and withdrawals; no concrete protocol-level loss is shown from the code provided. |
| trust_or_owner_model | opencode_1 | Unlimited Owner Control Over Token Transfers | This is the intended owner-controlled pause mechanism (`enable`), not an implementation flaw. |
| trust_or_owner_model | opencode_1 | Single-Point Proposal Role Modification | Governance centralization/trust-model issue only. No bug beyond the privileged role already being powerful by design. |
| trust_or_owner_model | opencode_1 | Migration Without User Consent | Governance migration authority is explicit design, not a code vulnerability absent a stronger implementation bug. |
| other | opencode_1 | Potential Division by Zero in VaultMath | False positive. `VaultMath` guards on `_assetPerShare > 1`; the cited total-supply scenario is unrelated to these pure math helpers. |
| other | opencode_1 | Daily Quota Can Be Fully Consumed by Single User | This is the documented behavior of a global daily cap, not a vulnerability. |
| other | opencode_1 | Unchecked Return Value in Strategy Withdrawal | The cited contract is an abstract base with virtual stubs, not deployed logic. No concrete vulnerable implementation is shown. |
| trust_or_owner_model | opencode_1 | AssetsVault Can Be Reinitialized | `setNewVault()` is an intended privileged migration hook and depends on already-authorized callers; this is not a separate bug. |
| other | opencode_1 | No Access Control on Stone Contract Initialization | Constructor initialization is only performed at deployment. Setting an undesirable initial cap is configuration risk, not a vulnerability. |
