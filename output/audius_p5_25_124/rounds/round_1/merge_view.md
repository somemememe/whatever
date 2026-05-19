# Merge View - Round 1

## Summary
- total findings: 7
- new findings: 7
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 5

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | Funding-block claims can be replayed and reorder payouts because the round snapshot is mutable within the same block | codex_1:0.522 Round-start claims can be replayed or reordered in the funded block to overmint rewards |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Matured stake-removal actions remain executable during a pending-claim window, letting providers claim against stake they already removed | codex_1:0.594 Pre-scheduled stake removals can be executed during a pending claim window to steal or inflate rewards |
| F-003 | rewritten_agent_signal | Medium | high | codex_1 | Dust-stake accounts can fill every governance proposal slot and repeatedly delay protocol actions | codex_1:0.584 Any dust staker can monopolize all proposal slots and repeatedly stall governance |
| F-004 | exact_agent_candidate | Medium | medium | codex_1 | A guardian proposal submitted when total stake is zero can become permanently unevaluable and block new proposals | codex_1:0.881 A guardian proposal submitted when total stake is zero can become permanently unevaluable |
| F-005 | rewritten_agent_signal | Medium | medium | codex_1 | Governance proposal code-hash pinning does not detect proxy implementation upgrades | codex_1:0.817 Governance's target-code hash check does not detect proxy implementation upgrades |
| F-006 | exact_agent_candidate | Low | high | codex_1 | Claims use the mutable global `fundingAmount` instead of the round's snapshotted `fundedAmount` | codex_1:1.0 Claims use the mutable global `fundingAmount` instead of the round's snapshotted `fundedAmount` |
| F-007 | rewritten_agent_signal | Medium | medium | opencode_1 | Permissionless `claimRewards` can burn a provider's entire round by finalizing a zero-value claim during temporary ineligibility | codex_1:0.339 Pre-scheduled stake removals can be executed during a pending claim window to steal or inflate rewards |

## Rejection Reasons
- other: 4
- trust_or_owner_model: 2
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | DelegateManager.claimRewards allows unauthorized reward claims | Caller control is missing, but the function does not redirect rewards to the caller; rewards are credited to the specified service provider and delegators. Reconstructed separately as a grief-only zero-value claim issue, not theft. |
| other | opencode_1 | Guardian can execute arbitrary transactions without voting | This is an explicit guardian privilege in the protocol design, not a bug in the implemented access control. |
| other | opencode_1 | Initializable initializer modifier blocks contract initialization | The initializer checks `proxyAdmin` in proxy storage; this code alone does not show initialization is impossible, and the proxy pattern is intended to supply that slot. |
| trust_or_owner_model | opencode_1 | Registry has single point of failure with onlyOwner access | This is a governance/trust-model centralization concern rather than a distinct implementation vulnerability. |
| unsupported_or_speculative | opencode_1 | ServiceProviderFactory _validateBalanceInternal missing deployerStake validation | Rejected as stated: registration validates current deployer stake against the minimum, and `decreaseStake()` revalidates after updating `deployerStake`, so the claimed bypass is not supported. |
| unsupported_or_speculative | opencode_1 | ClaimsManager processClaim potential division by zero | Too speculative as a standalone reportable issue here; reaching `totalStakedAt(fundedBlock) == 0` for a claimable provider depends on zero-minimum service-type configuration, and no distinct persistent harmful state beyond that edge case is demonstrated. |
| trust_or_owner_model | opencode_1 | ServiceProviderFactory allows registration with zero stake | Not unconditional: `register()` immediately calls stake-balance validation, so zero-stake registration only succeeds if governance created a service type with `minStake == 0`. |
| other | opencode_1 | Governance guardian can transfer guardianship to zero address | This is trusted-role self-misconfiguration, and the guardian already holds stronger powers such as veto and arbitrary guardian execution; it is not a distinct adversarial vulnerability. |
