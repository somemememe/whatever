# Merge View - Round 1

## Summary
- total findings: 11
- new findings: 11
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- exact_agent_candidate: 4
- rewritten_agent_signal: 7

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | FSushiBill deposit/withdraw updates bill balances twice, creating unbacked bill supply and inflated reward weight | codex_1:0.833 FSushiBill deposit/withdraw mutates balances twice, inflating bill supply and reward weight |
| F-002 | exact_agent_candidate | Critical | high | codex_1 | FSushiBill backdates rewards for fresh beneficiaries because deposits never checkpoint the receiver | codex_1:1.0 FSushiBill backdates rewards for fresh beneficiaries because deposits never checkpoint the receiver |
| F-003 | exact_agent_candidate | Critical | high | codex_1 | FarmingLPToken transfers duplicate accrued vault rewards to the recipient | codex_1:1.0 FarmingLPToken transfers duplicate accrued vault rewards to the recipient |
| F-004 | exact_agent_candidate | High | medium | codex_1 | FarmingLPToken mints shares from attacker-controlled spot quotes instead of realized value | codex_1:1.0 FarmingLPToken mints shares from attacker-controlled spot quotes instead of realized value |
| F-005 | rewritten_agent_signal | Critical | high | codex_1 | FlashStrategySushiSwap flash-burn consumes principal-bearing fLP shares while principal accounting stays unchanged | codex_1:0.802 FlashStrategySushiSwap flash-burn unwraps staker principal while principal accounting remains unchanged |
| F-006 | rewritten_agent_signal | High | high | codex_1 | FSushiBar deposits for another beneficiary split the lock record from the burnable shares | codex_1:0.644 FSushiBar deposits for another beneficiary create unrecoverable lock/share mismatches |
| F-007 | exact_agent_candidate | Medium | high | codex_1,opencode_1 | FSushiBarPriorityQueue overwrites same-timestamp lock snapshots and can lose deposits | codex_1:0.911 FSushiBarPriorityQueue overwrites same-timestamp locks and loses deposits |
| F-008 | rewritten_agent_signal | High | high | codex_1 | Snapshots.valueAt uses the current block timestamp instead of the requested historical timestamp | codex_1:0.475 Broken snapshot lookup makes current kitchen weights rewrite historical emissions |
| F-009 | rewritten_agent_signal | Critical | high | codex_1 | FSushiAirdropsVotingEscrow reconstructs old weeks from only the latest voting-escrow checkpoints | codex_1:0.66 FSushiAirdropsVotingEscrow uses only latest voting-escrow checkpoints for historical weeks, breaking claims |
| F-010 | rewritten_agent_signal | High | high | opencode_1 | FSushiAirdropsVotingEscrow.claim() divides by zero on weeks with zero voting-escrow supply | codex_1:0.528 FSushiAirdropsVotingEscrow uses only latest voting-escrow checkpoints for historical weeks, breaking claims |
| F-011 | rewritten_agent_signal | Medium | high | codex_1 | FarmingLPToken standard withdraw and migrate paths revert whenever no Sushi yield is currently claimable | codex_1:0.825 FarmingLPToken blocks normal withdrawals and migrations whenever no Sushi yield is currently claimable |

## Rejection Reasons
- duplicate_or_subsumed: 2
- other: 9
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Division by zero causes revert in FSushiAirdropsVotingEscrow.claim() | Merged as F-010 with narrowed root cause and impact: the issue is specifically unguarded zero `totalSupply` during per-week payout calculation. |
| other | opencode_1 | Inverted Bankrupt check allows unlimited deposits | Rejected. Allowing deposits when `totalSupply == 0` is the necessary initialization path for the vault, not an exploitable invariant break. |
| duplicate_or_subsumed | opencode_1 | Unchecked arithmetic in FarmingLPToken._transfer allows theft of shares | Rejected as stated. Ordinary rounding in `shares = amount * sharesOf(from) / balance` is not the reportable bug; the real exploitable issue is the duplicated reward correction captured separately in F-003. |
| other | opencode_1 | Missing zero address validation in FSushiAirdrops.claim() | Rejected. `FSushi.mint()` ultimately uses OpenZeppelin ERC20 `_mint`, which already reverts on `address(0)`, so this is not a silent burn path. |
| duplicate_or_subsumed | opencode_1 | Unsafe int128 to uint256 cast in FSushiAirdropsVotingEscrow._votingEscrowBalanceOf | Rejected as a separate finding. The realistic failure mode is the use of the latest checkpoint for historical timestamps, which is already captured in F-009. |
| other | opencode_1 | Unchecked arithmetic in FSushiBar checkpoint can overflow | Rejected. Solidity 0.8 checked arithmetic makes these additions revert on overflow; no practical overflow exploit is present. |
| other | opencode_1 | Fee-on-transfer token vulnerability in FarmingLPToken | Rejected. The underlying asset is a UniswapV2 LP token selected from MasterChef, not an arbitrary fee-on-transfer token. |
| trust_or_owner_model | opencode_1 | Lack of access control on FlashStrategySushiSwapFactory.createFlashStrategySushiSwap | Rejected. Public creation is consistent with deterministic-per-pid factory deployment and does not let an attacker choose malicious implementation, parameters, or ownership. |
| other | opencode_1 | EmergencyWithdraw silently discards unclaimed yield | Rejected. This is an explicit emergency-only escape hatch (`EMERGENCY ONLY`) rather than an unintended protocol vulnerability. |
| other | opencode_1 | Potential timestamp collision in FSushiBarPriorityQueue | Merged into F-007. |
| other | opencode_1 | Right shift produces zero rewards after 256 weeks in FSushiAirdropsVotingEscrow | Rejected. This is an emission-schedule design choice from repeated right-shifting, not a security vulnerability by itself. |
| other | opencode_1 | Precision loss in FarmingLPToken.withdraw can lock user funds | Rejected. Standard pro-rata integer rounding may leave dust but does not by itself create a realistic fund-lock or theft issue at protocol level. |
