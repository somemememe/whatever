You are auditing the smart contracts in /Users/lu/Desktop/Red_V1G/targets/sherlock_968/scope.

## Contracts in Scope

# Scope

- superfluid-finance/fluid/packages/contracts/src/EPProgramManager.sol (351 LOC) — TODO
- superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol (661 LOC) — TODO
- superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol (874 LOC) — TODO
- superfluid-finance/fluid/packages/contracts/src/FluidLockerFactory.sol (223 LOC) — TODO
- superfluid-finance/fluid/packages/contracts/src/Fontaine.sol (178 LOC) — TODO
- superfluid-finance/fluid/packages/contracts/src/StakingRewardController.sol (262 LOC) — TODO
- superfluid-finance/fluid/packages/contracts/src/interfaces/IEPProgramManager.sol (214 LOC) — TODO
- superfluid-finance/fluid/packages/contracts/src/interfaces/IStakingRewardController.sol (189 LOC) — TODO
- superfluid-finance/fluid/packages/contracts/src/vesting/SupVesting.sol (150 LOC) — TODO
- superfluid-finance/fluid/packages/contracts/src/vesting/SupVestingFactory.sol (231 LOC) — TODO
- superfluid-org/protocol-monorepo/packages/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol (1982 LOC) — TODO
- superfluid-org/protocol-monorepo/packages/ethereum-contracts/contracts/utils/MacroForwarder.sol (41 LOC) — TODO

# Notes

- Auto-generated file-level map.
- Descriptions are placeholders and can be edited later.




## Known Findings (do NOT repeat — find NEW issues)

- F-001: Staked balance can be reused as LP principal while staking units remain active (High, high)
- F-002: Anyone can stop program funding during the early-end window (High, high)
- F-003: Unit-update signatures are replayable across deployments and chains (Medium, high)
- F-004: Repeated startFunding leaves residual treasury and subsidy streams (Medium, high)
- F-005: Pumponomics swap has no slippage bound (Medium, high)
- F-006: Fontaine unlocks can be terminated by any account in the final day (Low, high)
- F-007: Permissionless EPProgramManager can cache a malicious SuperToken host and GDA (Medium, low)
- F-008: Partial unstake disconnects the locker while staker units remain nonzero (Low, medium)
- F-009: Locker and Fontaine implementations snapshot pool addresses before setup can complete (Medium, medium)
- F-010: Permissionless base program manager allows irreversible program ID squatting (Medium, low)
- F-011: Zero-unit tax pools freeze instant and short unlocks (Medium, high)
- F-012: Permissionless tax adjustment distribution can force an unfavorable reward snapshot (Low, medium)
- F-013: Funding streams are not automatically terminated at program end (High, high)
- F-014: Requested subsidy rates can undercut the shared subsidy stream for active programs (Medium, medium)
- F-016: Non-FLUID program tokens can create unfundable or unwithdrawable locker rewards (Medium, low)
- F-017: Treasury flow underflow clamp can stop funding for unrelated active programs after flow drift (Medium, low)
- F-018: Minimum unlock amount can strand sub-10 SUP locker balances (Low, high)
- F-019: Liquidity withdrawal applies an extra 5% haircut to caller-provided minimums (Medium, high)
- F-020: Factory ETH fees can become stuck when governor is a contract receiver (Low, high)
- F-021: Direct execution of claim signatures can consume the nonce before locker pool connection (Low, medium)
- F-022: LP withdrawal path bypasses the locker unlock-availability gate (High, high)
- F-023: Streaming unlocks and vesting schedules are funded without Superfluid flow buffers (Medium, medium)
- F-024: Program funding accounts requested GDA flow rates instead of actual rates (Medium, medium)
- F-025: Unlock tax distributions can return GDA-clipped tax to the recipient (Medium, medium)
- F-026: Normal program stop leaves the initial deposit residue in the manager (Low, high)
- F-027: Emergency vesting deletion permanently blocks recreating a recipient schedule (Low, medium)

## Optional Prior Round Summary

An optional prior round summary is available at:
- `/Users/lu/Desktop/Red_V1G/AuditHoundV2/output/sherlock968_codex_opencode_3r/rounds/round_7/round_summary.md`

Read it only if useful, and think it before you use it.It may not be very concise.


## Optional Global Audit Memory

An optional global audit memory is available at:
- `/Users/lu/Desktop/Red_V1G/AuditHoundV2/output/sherlock968_codex_opencode_3r/global_summary.md`

Read it only if useful. It is historical context, not a coverage guarantee,
not proof that any area is safe, and not a priority list.


## Task

Find security vulnerabilities in the contracts listed above as more as you can.And there are lots of high severity vulns.

You should look for:
- vulnerabilities
- reportable issues

Audit only Solidity source files under the target directory above.
Do not inspect or rely on files outside that directory, including README, docs, audit reports, discord exports, scripts, broadcasts, or other repository context, unless they are explicitly included in the target directory.

If you identify a problem that is not fully proven, still report it as a low-confidence finding.
Be skeptical of documented behavior and pure owner-only configuration issues, but you may still report them when they create realistic protocol-level harm such as fund loss, theft, insolvency, permanent lockup, economic manipulation, or permissionless denial of service.

## Output Format

Return ONLY a JSON array.

Each element must have:
- `id`: local finding id such as `F-001`
- `severity`: `Critical` / `High` / `Medium` / `Low` / `Informational`
- `confidence`: `high` / `medium` / `low`
- `title`: one-line summary
- `locations`: array of `file:line`
- `claim`: core mechanism statement
- `impact`: why it matters
- `paths`: array of trigger/exploit paths, may be empty

If there are no findings, return `[]`.
