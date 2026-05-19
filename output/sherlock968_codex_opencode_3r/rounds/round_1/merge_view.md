# Merge View - Round 1

## Summary
- total findings: 8
- new findings: 8
- updated existing findings: 0
- rejected candidates: 12

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 7

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | Staked balance can be reused as LP principal while staking units remain active | codex_1:0.608 Staked balance can be rehypothecated into LP while still earning staking rewards |
| F-002 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Anyone can stop program funding during the early-end window | codex_1:0.8 Any account can forcibly stop active program funding during early-end window |
| F-003 | exact_agent_candidate | Medium | high | codex_1 | Unit-update signatures are replayable across deployments and chains | codex_1:0.859 Unit-update signatures are replayable across contracts/chains |
| F-004 | rewritten_agent_signal | Medium | high | codex_1,opencode_1 | Repeated startFunding leaves residual treasury and subsidy streams | codex_1:0.792 Repeated startFunding on same program leaves untracked residual treasury/subsidy streams |
| F-005 | rewritten_agent_signal | Medium | high | codex_1 | Pumponomics swap has no slippage bound | codex_1:0.424 Pumponomics swap uses zero minimum output and is sandwichable |
| F-006 | rewritten_agent_signal | Low | high | codex_1,opencode_1 | Fontaine unlocks can be terminated by any account in the final day | codex_1:0.523 Fontaine unlock termination is permissionless |
| F-007 | rewritten_agent_signal | Medium | low | codex_1 | Permissionless EPProgramManager can cache a malicious SuperToken host and GDA | opencode_1:0.464 Missing Access Control on FluidEPProgramManager.stopFunding() |
| F-008 | rewritten_agent_signal | Low | medium | opencode_1 | Partial unstake disconnects the locker while staker units remain nonzero | codex_1:0.395 Staked balance can be rehypothecated into LP while still earning staking rewards |

## Rejection Reasons
- factually_incorrect: 2
- low_impact_or_operational: 1
- other: 5
- trust_or_owner_model: 2
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| factually_incorrect | opencode_1 | Missing reentrancy guard on FluidLocker.withdrawLiquidity() | The reported function is explicitly protected with `nonReentrant` at `FluidLocker.sol:452`; the signal is factually incorrect. |
| other | opencode_1 | StakingRewardController.distributeTaxAdjustment() requires access control | The function only distributes the controller's current FLUID balance according to the already configured allocation and gives the caller no direct benefit. The signal describes keeper-style permissionlessness and does not show realistic protocol harm. |
| low_impact_or_operational | opencode_1 | Missing event emission in FluidLocker.provideLiquidity() | Missing telemetry is an observability issue, not a protocol-level vulnerability causing loss, theft, insolvency, lockup, manipulation, or permissionless DoS. |
| other | opencode_1 | MacroForwarder.runMacro() is permissionless | The upstream forwarder is intentionally permissionless; macros are built with `msg.sender`, and Superfluid authorization still gates operations. The report does not identify a concrete path to move funds or alter flows without the affected account's permissions. |
| unsupported_or_speculative | opencode_1 | SupVestingFactory rounding causes cliffAmount to exceed total amount | The remainder logic preserves the total schedule: updated cliff plus streamed `flowRate * duration` equals the original amount. The claimed over-allocation is not supported by the arithmetic. |
| trust_or_owner_model | opencode_1 | FluidEPProgramManager inconsistent program admin assignment | The owner selecting a nonzero `programAdmin` during creation is an intended permission model, and no exploit path or protocol-level harm was identified. |
| other | opencode_1 | FluidEPProgramManager flow-rate division precision loss | Integer truncation can leave small amounts undistributed or require conservative allowances, but the signal does not show loss to users or exploitable extraction; it is normal fixed-rate streaming dust. |
| unsupported_or_speculative | opencode_1 | FluidLocker.unlock() missing recipient contract compatibility check | The code checks `recipient != address(0)`, and Fontaine initialization rejects SuperApps. The report's ERC777 hook concern is not supported by the shown SuperToken transfer/flow usage. |
| trust_or_owner_model | opencode_1 | SupVesting infinite approval to vesting scheduler | The scheduler is an immutable constructor dependency, and the attack requires the trusted scheduler or its governance to become malicious. That is an external trust-assumption failure, not a bug in this code path. |
| other | opencode_1 | StakingRewardController tax allocation not initialized | This is a deployment/configuration concern. Without a concrete attacker-controlled transition, default allocation behavior is not a reportable protocol vulnerability. |
| other | codex_1 | Factory ETH withdrawal can fail permanently due to transfer stipend | `withdrawETH()` can fail for a governor contract with an expensive receiver, but the same governor can call `setGovernor()` to rotate withdrawals to a compatible address. The candidate does not establish permanent lockup or realistic protocol-level harm. |
| factually_incorrect | opencode_1 | Fontaine.terminateUnlock() lets the caller steal remaining tokens | The theft impact is incorrect: after termination, provider and staker compensation is distributed to their pools and leftover FLUID is transferred to the configured recipient, not to the caller. The supported portion was merged only as a low-severity timing/snapshot issue. |
