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
# Global Audit Memory

## Scope Touched
- `Staking.sol` — persistent audit hotspot; recurring attention on `deposit`, `withdraw`, `emergencyWithdraw`, `manualEpochInit`, epoch snapshot/history helpers, pool-size reads, and Compound mint/redeem + interest-sweep paths
- `Contract.sol` — mainly a wrapper/container for the embedded staking system; useful for navigating embedded logic rather than a separate logic hotspot
- embedded `SafeERC20.sol` / transfer helpers — lightly revisited for transfer-result assumptions that can amplify staking accounting or payout inconsistencies

## Issue Directions Seen
- Token/accounting mismatch paths: internal stake/claim accounting can diverge from assets actually moved, especially around non-standard ERC-20 behavior, external integration failures, and balance-based accounting
- Emergency/withdraw liveness fragility: exit flows appear sensitive to liquidity shortfalls, incomplete accounting cleanup, and skipped/stale epoch state
- Epoch progression and snapshot integrity: historical pool-size views and epoch-dependent behavior remain exposed to stale, mutable, or backfilled state
- Compound integration safety: weak enforcement of `mint` / `redeem` success and liquidity assumptions can leak into withdrawal availability and internal bookkeeping
- Non-stable pool valuation/snapshot risk: some accounting paths appear to trust raw `balanceOf` views over tracked stake totals, creating pool-size divergence risk
- Permissionless interest-sweep pressure: publicly callable interest/redemption flows may let third parties reorder liquidity usage in ways that worsen withdrawal shortfalls

## Useful Context
- Audit attention remains concentrated in one effective contract surface, with the dominant theme being bookkeeping consistency under imperfect asset movement and external liquidity constraints rather than classic privilege misuse
- The same accounting surfaces recur across normal withdrawals, emergency exits, manual epoch initialization, historical snapshot reads, and interest handling, indicating strong coupling between liveness and accounting correctness
- Historical/epoch helpers are part of the practical attack surface because current-state mutations can affect both past-epoch reads and whether later user actions remain executable
- Embedded helper/library code has seen only light review; most durable risk still comes from how staking logic consumes token balances, transfer outcomes, and Compound availability assumptions


## Latest Round Summary
# Round 4 Summary

## Agent: codex
- files touched: `Contract.sol` only; within it, the review extracted and inspected embedded `Staking.sol` and `SafeERC20.sol`
- files revisited / highest-attention files: `Staking.sol` received the main attention, especially `deposit`, `withdraw`, `emergencyWithdraw`, Compound transfer/redeem helpers, epoch helpers, and referral/reward-related state; `SafeERC20.sol` was revisited for approval behavior
- main issue directions investigated: staking state transitions; token/epoch accounting; emergency exit gating; Compound mint/redeem integration behavior; approval handling for stablecoins; hardcoded token/cToken address assumptions
- promising but not retained directions: referral/reward paths and owner-controlled percentage updates were checked but not retained; a quick tooling/static pass was attempted, but no additional retained result came from it

## Cross-Agent Status
- main overlap in file/area attention: only one agent participated, with concentrated attention on the staking core and Compound-related stablecoin paths inside the embedded `Staking.sol`
- notable differences in attention: no cross-agent differences this round
- underexplored but suspicious files/functions if clearly supported by the logs: referral handling (`processReferrals`, `updateReferrersPercentage`) was inspected briefly relative to the heavier focus on withdrawal/emergency and Compound flows

## Retained Findings
- no findings were retained from this round after merge


Output only markdown.
