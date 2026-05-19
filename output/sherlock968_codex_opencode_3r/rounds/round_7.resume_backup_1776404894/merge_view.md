# Merge View - Round 7

## Summary
- total findings: 26
- new findings: 6
- updated existing findings: 1
- rejected candidates: 11

## Finding Actions
- exact_agent_candidate: 5
- existing_preserved: 19
- existing_rewritten: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-017 | existing_rewritten | Medium | low | codex_1 | Treasury flow underflow clamp can stop funding for unrelated active programs after flow drift | opencode_1:0.436 No automatic termination of funding streams at program end date |
| F-022 | exact_agent_candidate | High | high | codex_1 | LP withdrawal path bypasses the locker unlock-availability gate | codex_1:1.0 LP withdrawal path bypasses the locker unlock-availability gate |
| F-023 | exact_agent_candidate | Medium | medium | codex_1 | Streaming unlocks and vesting schedules are funded without Superfluid flow buffers | codex_1:1.0 Streaming unlocks and vesting schedules are funded without Superfluid flow buffers |
| F-024 | exact_agent_candidate | Medium | medium | codex_1 | Program funding accounts requested GDA flow rates instead of actual rates | codex_1:1.0 Program funding accounts requested GDA flow rates instead of actual rates |
| F-025 | rewritten_agent_signal | Medium | medium | codex_1 | Unlock tax distributions can return GDA-clipped tax to the recipient | codex_1:0.679 Vested unlock tax flows ignore actual GDA rates and can return clipped tax to the recipient |
| F-026 | exact_agent_candidate | Low | high | codex_1 | Normal program stop leaves the initial deposit residue in the manager | codex_1:0.887 Normal program stop leaves the initial flow buffer residue in the manager |
| F-027 | exact_agent_candidate | Low | medium | codex_1 | Emergency vesting deletion permanently blocks recreating a recipient schedule | codex_1:1.0 Emergency vesting deletion permanently blocks recreating a recipient schedule |

## Rejection Reasons
- duplicate_or_subsumed: 4
- factually_incorrect: 1
- other: 3
- trust_or_owner_model: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | opencode_1 | Permissionless distributeTaxAdjustment allows front-running of reward distribution | Already covered by F-012. The new path claiming attackers can skew allocation ratios with token transfers is not supported because allocation comes from stored taxAllocation and pool units, not caller token transfers. |
| other | opencode_1 | Partial unstake disconnects locker from staker pool while maintaining non-zero units | Already covered by F-008. The high-severity/permanent-loss framing is overstated because the issue is a reward-connection liveness/accounting problem, not theft of principal. |
| duplicate_or_subsumed | opencode_1 | No automatic termination of funding streams at program end date | Duplicate of F-013. |
| other | opencode_1 | Liquidity provision allows zero-length position creation without LP pool connection | The code connects to `LP_DISTRIBUTION_POOL` and updates LP units inside `_createPosition()`. Pool-readiness/stale-address concerns are already covered by F-009. |
| duplicate_or_subsumed | opencode_1 | Repeated startFunding creates residual subsidy streams from previous programs | Duplicate of F-004. |
| trust_or_owner_model | opencode_1 | Unrestricted emergencyWithdraw can drain all tokens including locked rewards | `emergencyWithdraw()` is owner-restricted, so the malicious-admin framing is not independently reportable. The non-malicious residue recovery risk is captured in F-026. |
| duplicate_or_subsumed | opencode_1 | Fontaine terminateUnlock callable by anyone during final day | Duplicate of F-006. The claim that the caller captures compensation is incorrect; funds go to the recipient and distribution pools. |
| trust_or_owner_model | opencode_1 | Tax-free withdrawal timestamp not validated before liquidity removal | The paired ETH/WETH is supplied by the locker owner for liquidity and is not subject to the SUP tax-free delay. Immediate ETH return is expected behavior, not a protocol-loss issue. |
| duplicate_or_subsumed | opencode_1 | Pumponomics swap lacks slippage protection for market purchases | Duplicate of F-005. |
| factually_incorrect | opencode_1 | Unit update signatures replayable across different programs due to missing programId in batch verification | Rejected as incorrect. The batch signature hash includes the `programIds` array, and reordering the array changes the signed digest. |
| other | codex_1 | Program pools can lose all units after funding starts and strand active funding | Folded into F-024 to the extent the harm is caused by actual GDA flow falling below the requested funding rate. The stronger standalone claim that normal finalization is blocked by an empty pool was not established from the code. |
