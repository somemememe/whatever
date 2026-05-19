# Merge View - Round 1

## Summary
- total findings: 6
- new findings: 6
- updated existing findings: 0
- rejected candidates: 9

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | Upgradeable presale exposes no initializer, leaving proxy owner and all core configuration permanently unset | codex_1:0.894 Upgradeable presale has no initializer, leaving owner and all core config permanently unset |
| F-002 | rewritten_agent_signal | Medium | high | codex_1 | Claim functions ignore claimStart and allow early withdrawals or staking | opencode_1:0.345 claimAndStake deletes userDeposits before verifying staking success |
| F-003 | exact_agent_candidate | High | high | codex_1,opencode_1 | Claim funding check is ineffective because totalTokensSold is never updated | codex_1:1.0 Claim funding check is ineffective because totalTokensSold is never updated |
| F-004 | rewritten_agent_signal | Medium | medium | codex_1,opencode_1 | USDT purchase paths treat any non-reverting low-level call as successful payment | codex_1:0.703 USDT purchase paths accept non-reverting calls as payment success |
| F-005 | rewritten_agent_signal | Medium | high | codex_1 | Staking manager address is never validated, so purchase and claim-and-stake flows can succeed while recording no stake | codex_1:0.837 Staking manager is never validated, so purchases can succeed while recording no stake |
| F-006 | rewritten_agent_signal | Medium | high | codex_1,opencode_1 | Configured sale window is dead code because none of the buy functions enforce startTime or endTime | codex_1:0.52 Configured sale window is dead code and does not restrict any purchase path |

## Rejection Reasons
- duplicate_or_subsumed: 1
- factually_incorrect: 1
- low_impact_or_operational: 1
- other: 4
- trust_or_owner_model: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Missing nonReentrant modifier on USDT buy functions | The concrete risk here is the unsafe low-level USDT payment handling itself; a separate reentrancy finding was not substantiated beyond the same misconfigured/malicious-token assumption and did not show an additional protocol-harm path. |
| duplicate_or_subsumed | opencode_1 | Owner can change staking contract to any address | As stated, this is an owner-privilege observation rather than an independent vulnerability. The reportable issue is the lack of validation that allows accidental misconfiguration to silently break staking flows, which is already captured in F-005. |
| factually_incorrect | opencode_1 | Unlimited token approval in startClaim without revocation | Changing stakingContract later does not grant the new address the old approval; the approval remains with the address approved in startClaim. The candidate's drain path is incorrect as written and reduces to trusted-admin risk. |
| other | opencode_1 | Division before multiplication causes precision loss | The ETH path already multiplies before dividing, and the USDT path's decimal conversion only introduces normal rounding/truncation. No realistic fund-loss or exploitable protocol-level harm was supported. |
| other | opencode_1 | claimAndStake deletes userDeposits before verifying staking success | If depositByPresale reverts, the whole transaction reverts and userDeposits is not deleted. The real issue is silent success against an invalid staking target, which is covered by F-005. |
| other | opencode_1 | No slippage protection on token purchases | This is a fixed-price sale flow, not an AMM swap. The absence of a min-out parameter is not a standalone vulnerability on the shown code paths. |
| low_impact_or_operational | opencode_1 | Missing events for critical administrative functions | This is observability/code-quality feedback, not a realistic protocol-harm issue. |
| trust_or_owner_model | opencode_1 | No access control on updateFromBSC function | The function is gated by onlyOwner. Arbitrary owner-controlled imports are a trust/centralization property, not a missing-access-control bug. |
| trust_or_owner_model | opencode_1 | stakeingWhitelistStatus can be disabled after claims start | This is an owner-controlled policy toggle with no unsupported access path. It does not constitute an independent vulnerability. |
