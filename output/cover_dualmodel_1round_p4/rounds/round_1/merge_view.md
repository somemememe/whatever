# Merge View - Round 1

## Summary
- total findings: 6
- new findings: 6
- updated existing findings: 0
- rejected candidates: 7

## Finding Actions
- exact_agent_candidate: 6

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | New deposits can capture COVER rewards accrued before they were staked | codex_1:0.955 New deposits can capture rewards accrued before they were staked |
| F-002 | exact_agent_candidate | High | high | codex_1 | Shared bonus-token accounting lets one pool drain another pool's bonus reserves | codex_1:1.0 Shared bonus-token accounting lets one pool drain another pool's bonus reserves |
| F-003 | exact_agent_candidate | High | high | codex_1 | SAFE2 migrations can exceed the advertised migration cap | codex_1:1.0 SAFE2 migrations can exceed the advertised migration cap |
| F-004 | exact_agent_candidate | Medium | high | codex_1,opencode_1 | Deposits over-credit fee-on-transfer or deflationary LP tokens | codex_1:1.0 Deposits over-credit fee-on-transfer or deflationary LP tokens |
| F-005 | exact_agent_candidate | Medium | high | codex_1 | Reward-parameter changes apply retroactively to already elapsed time | codex_1:1.0 Reward-parameter changes apply retroactively to already elapsed time |
| F-006 | exact_agent_candidate | Medium | high | codex_1 | Team vesting can release arbitrary ERC20s, not just COVER | codex_1:1.0 Team vesting can release arbitrary ERC20s, not just COVER |

## Rejection Reasons
- other: 5
- trust_or_owner_model: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Migrator can change itself and mint unlimited COVER tokens | `COVER.setMigrator()` can only be called by the current migrator contract, and the only exposed path that makes that call is `Migrator.transferMintingRights()`, which is restricted to governance. This is an explicit governance-controlled handoff, not a permissionless mint bug. |
| other | opencode_1 | Emergency withdraw loses pending rewards | `emergencyWithdraw()` is explicitly documented as `withdraw all without rewards`; forfeiting accrued rewards is the intended tradeoff of the emergency path, not an unintended vulnerability. |
| other | opencode_1 | BitMap index overflow potential in Migrator | The bit index is bounded by `_index % 256`, so the shift is always in the safe 0-255 range and does not create an overflow condition. |
| other | opencode_1 | Precision loss in reward calculations | The code already uses fixed-point scaling via `CAL_MULTIPLIER`; remaining integer truncation only creates minor dust and does not support a realistic exploit or material loss scenario. |
| other | opencode_1 | Missing nonReentrant on vesting function | `vest()` updates `_vested[msg.sender]` before the external token transfer, so a reentrant callback cannot increase the caller's releasable amount or double-claim. |
| other | opencode_1 | Claim function allows any caller to claim on behalf of any address | The Merkle leaf is `keccak256(abi.encodePacked(_index, msg.sender, _amount))`, so the proof is bound to the caller's address and cannot be front-run by an arbitrary third party claiming for someone else. |
| trust_or_owner_model | opencode_1 | Weekly total can be set to zero causing reward halt | `weeklyTotal` is an intentional governance-controlled emissions parameter. Setting it to zero is an admin decision, not an unintended protocol bug. |
