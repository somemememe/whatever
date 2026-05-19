You maintain a concise global audit memory for future audit agents.

Update the existing global memory by folding in durable observations from the
latest round summary. The goal is an accumulated cross-round audit view, not a
per-round recap.

This memory is optional context only. Findings are stored separately.

Write the updated memory in this exact structure:

# Global Audit Memory

## Scope Touched
- files/contracts/flows that have mattered across rounds, with short issue-direction notes

## Issue Directions Seen
- recurring or promising vulnerability directions seen across the audit

## Useful Context
- compact cross-round observations 

Rules:
- keep it compact
- preserve useful prior context while integrating new durable observations
- prefer stable cross-round patterns over latest-round details
- fold repeated wording into a single clearer observation
- keep the memory descriptive rather than prescriptive

## Existing Global Memory
No global memory yet.

## Latest Round Summary
# Round 1 Summary

## Agent: codex_1
- files touched: `0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol`; read `@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol`
- files revisited / highest-attention files: `JuiceStaking.sol`, especially `stake()`, `harvest()`, `unstake()`, `pendingReward()`, `startStaking()`, and `rescueReward()`
- main issue directions investigated: unbounded `stakeWeek` bonus amplification; reward accounting versus funded inventory; insolvency/lockup risk from boosted payouts; owner withdrawal of economically owed rewards
- promising but not retained directions: immediate claiming of long-lock bonus before lock completion

## Agent: opencode_1
- files touched: `0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol`; read `@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol`
- files revisited / highest-attention files: `JuiceStaking.sol`
- main issue directions investigated: unstake reward accounting, hardcoded token configuration, staking-period setup limits, reward precision/truncation, missing pause/emergency controls
- promising but not retained directions: claimed double-counting in `unstake`; hardcoded token address risk; `rewardPerSecond` truncation; harvest-after-end and one-time `startStaking()` concerns

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated almost entirely on `JuiceStaking.sol`, especially reward accrual, payout, and pool-balance accounting
- notable differences in attention: `codex_1` focused on exploitable economic flaws and owner-drain behavior; `opencode_1` focused more on configuration, precision, and generic safety/control concerns
- underexplored but suspicious files/functions if clearly supported by the logs: no clearly supported hotspot outside `JuiceStaking.sol`; review attention was heavily concentrated there rather than in auxiliary OZ files

## Retained Findings
- Retained issues all came from `codex_1` and center on `JuiceStaking.sol` reward economics.
- The round retained: unbounded `stakeWeek` enabling arbitrarily large bonus extraction, systemic underfunding because configured rewards do not cover bonus liabilities, and `rescueReward()` allowing the owner to remove tokens already owed to active stakers.


Output only markdown.
