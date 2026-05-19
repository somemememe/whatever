# Merge View - Round 9

## Summary
- total findings: 30
- new findings: 3
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- exact_agent_candidate: 2
- existing_preserved: 27
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-029 | exact_agent_candidate | Medium | high | codex_1 | Treasury rotation can orphan active funding inflows from the previous treasury | codex_1:1.0 Treasury rotation can orphan active funding inflows from the previous treasury |
| F-030 | rewritten_agent_signal | Low | high | codex_1 | Early full LP withdrawal can strand withdrawn SUP inside the locker | codex_1:0.634 Early LP withdrawal can strand principal SUP in the locker without deferred-release accounting |
| F-032 | exact_agent_candidate | Low | high | codex_1 | Factory governor can be zeroed, permanently bricking admin controls | codex_1:1.0 Factory governor can be zeroed, permanently bricking admin controls |

## Rejection Reasons
- duplicate_or_subsumed: 2
- factually_incorrect: 1
- other: 2
- trust_or_owner_model: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex_1 | Permissionless third-party locker creation enables locker squatting for arbitrary addresses | `createLockerContract(address user)` appears intentionally permissionless for relayed/prepaid creation; locker ownership is still bound to `user`, so attacker control is not gained and concrete protocol-level harm is too speculative. |
| other | codex_1 | Batch unit-update signature hashing uses packed dynamic arrays without explicit length separation | For `uint256[]` arrays, `abi.encodePacked` uses fixed 32-byte elements; with validated equal lengths, the encoded boundaries are deterministic for the provided calldata and no practical collision/reinterpretation exploit is supported. |
| trust_or_owner_model | opencode_1 | SupVesting emergencyWithdraw allows admin to permanently delete any recipient's vesting | This is an explicit privileged emergency mechanism (`onlyAdmin`) rather than an unintended permission bypass; it is a trust-model choice, not a standalone code vulnerability. |
| duplicate_or_subsumed | opencode_1 | StakingRewardController distributeTaxAdjustment is permissionless enabling front-running | Duplicate of existing finding F-012. |
| duplicate_or_subsumed | opencode_1 | FluidEPProgramManager startFunding lacks active program check allowing duplicate funding | Duplicate of existing finding F-004. |
| other | opencode_1 | EPProgramManager batchUpdateUserUnits doesn't verify programs share same token | Batch updates only set per-program pool units and do not require a same-token invariant; no concrete cross-token exploit path is demonstrated from this omission alone. |
| factually_incorrect | opencode_1 | FluidLockerFactory uses CREATE2 with user salt creating irreversible address commitment | Premise is incorrect: lockers are BeaconProxy instances and existing lockers follow beacon implementation upgrades. |
| unsupported_or_speculative | opencode_1 | SupVestingFactory missing endDate validation allowing invalid vesting schedules | Claim is incomplete and unsupported; invalid `endDate` inputs revert via checked arithmetic/division, so they do not create persistent malformed schedules. |
