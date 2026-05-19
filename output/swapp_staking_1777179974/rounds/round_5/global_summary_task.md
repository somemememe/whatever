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
- `Staking.sol` — persistent hotspot; repeated focus on `deposit`, `withdraw`, `emergencyWithdraw`, `manualEpochInit`, epoch/history helpers, pool-size reads, and Compound mint/redeem plus interest-sweep liquidity paths
- Compound-facing stablecoin plumbing inside `Staking.sol` — recurring attention on cToken interactions, redeem/mint result handling, approval behavior, and hardcoded token/cToken address assumptions
- embedded `SafeERC20.sol` / transfer helpers — lightly revisited for transfer/approval return-value assumptions that can magnify staking accounting or payout inconsistencies
- referral/reward helpers (`processReferrals`, percentage-update state) — seen as adjacent surface but still secondary and comparatively underexplored versus withdrawal/liquidity logic
- `Contract.sol` — mainly serves as the container for the embedded staking system; useful for navigation more than as an independent logic surface

## Issue Directions Seen
- Token/accounting mismatch paths: internal stake or claim accounting can diverge from assets actually moved, especially with non-standard ERC-20 behavior, approval quirks, external integration failures, or balance-based accounting
- Emergency/withdraw liveness fragility: exit flows remain sensitive to liquidity shortfalls, incomplete accounting cleanup, and epoch state that is stale, skipped, or backfilled
- Epoch progression and snapshot integrity: historical pool-size views and epoch-dependent behavior continue to look exposed to mutable or stale state
- Compound integration safety: weak coupling between staking bookkeeping and `mint` / `redeem` success, redeemable liquidity, or fixed address assumptions can propagate into withdrawal availability
- Non-stable pool valuation/snapshot risk: some accounting paths appear to trust raw balance views over tracked stake totals, leaving room for pool-size divergence
- Permissionless interest-sweep pressure: publicly callable interest/redemption flows may let third parties reorder liquidity usage in ways that worsen withdrawal shortfalls

## Useful Context
- Audit attention stays concentrated on one effective contract surface, with the dominant theme being bookkeeping consistency under imperfect asset movement and external liquidity constraints rather than classic privilege misuse
- The same accounting surfaces recur across normal withdrawals, emergency exits, manual epoch initialization, historical snapshot reads, and interest handling, showing tight coupling between liveness and accounting correctness
- Historical/epoch helpers are part of the practical attack surface because present-state mutations can influence both past-epoch reads and whether later user actions remain executable
- Helper/library code has received only light review; durable risk continues to come mainly from how staking logic consumes token balances, approval outcomes, and Compound availability assumptions
- Referral/reward logic has been inspected but remains a lower-confidence, less-explored branch relative to the much heavier focus on withdrawal, emergency, and Compound-backed stablecoin flows


## Latest Round Summary
# Round 5 Summary

## Agent: codex
- files touched: `Contract.sol` (used as a JSON wrapper to inspect embedded Solidity sources); extracted and reviewed `Staking.sol` plus supporting interfaces/libraries (`CTokenInterface.sol`, `IERC20.sol`, `EIP20NonStandardInterface.sol`, `SafeERC20.sol`, `ReentrancyGuard.sol`)
- files revisited / highest-attention files: `Staking.sol` received the main review focus, especially `deposit`, `getInterest`, `withdraw`, `manualEpochInit`, epoch helpers, and Compound-related flows
- main issue directions investigated: epoch initialization and snapshot propagation; stablecoin/Compound interest accounting; checkpoint and multiplier behavior; external token/cToken interaction semantics
- promising but not retained directions: a possible over-100% epoch-0 multiplier issue around `currentEpochMultiplier()` / early deployment timing was explored and reported by the agent, but it was not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: only `codex` is present in this round’s logs, with concentrated attention on `Staking.sol`
- notable differences in attention: none visible from the logs because only one agent is recorded for this round
- underexplored but suspicious files/functions if clearly supported by the logs: supporting token/Compound wrapper files were only lightly checked to confirm call semantics, while review remained centered on `Staking.sol`

## Retained Findings
- `manualEpochInit()` can overwrite an already-populated epoch-0 pool snapshot, allowing a forged zero baseline to be propagated into later lazily initialized epochs
- `getInterest()` can sweep unrelated stablecoins sitting on the contract to `TEAM_ADDRESS`, not just genuine Compound-generated interest


Output only markdown.
