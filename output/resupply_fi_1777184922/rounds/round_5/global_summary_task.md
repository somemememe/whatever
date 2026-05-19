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
- `src/protocol/pair/ResupplyPairCore.sol` / `src/protocol/ResupplyPair.sol` — persistent audit center; borrow/collateral/liquidation/redemption accounting, solvency + exchange-rate refresh, full-redemption debt/share resets, fee paths, and external handler / Convex transitions
- Convex collateral management in `src/protocol/ResupplyPair.sol` — durable risk surface for credited collateral vs actual asset location, especially around staking, pool-switch, or migration state changes
- Oracle integration around `src/interfaces/IOracle.sol` and pair refresh paths — protocol-wide dependency for price normalization, inversion/decimals handling, freshness/sanity assumptions, and zero-price availability
- `src/protocol/RewardDistributorMultiEpoch.sol` — recurring liveness/accounting surface; checkpoint/integral and claim coupling can affect borrower-facing flows even when no finding is retained
- `src/protocol/WriteOffToken.sol` / `src/libraries/VaultAccount.sol` — supporting context for debt/share, writeoff, and redemption-side accounting behavior

## Issue Directions Seen
- Oracle math and refresh behavior remain a core direction: decimal mismatches, inversion logic, weak freshness/sanity assumptions, and zero-price availability failures
- Pair accounting vs real asset state is the strongest recurring theme, especially where redemptions, writeoffs, migrations, or external integrations let internal balances diverge from recoverable collateral
- Redemption/writeoff accounting is now a durable direction: borrower writeoff handling can misstate remaining collateral, and redemption edge cases interact with debt-share cleanup
- Full-redemption/reset logic remains a live accounting direction: when debt is fully cleared, stale global borrow-share state can survive and contaminate later borrowing cycles
- Reward distribution remains a secondary but recurring direction in two forms: zero-borrow-share accounting can strand rewards, and reward-claim execution can couple into borrow/repay/withdraw/liquidation liveness
- Convex integration remains live beyond staking-success assumptions: pool-management edge cases and sentinel/state encoding can orphan or live-lock collateral
- Handler-mediated redemption/liquidation settlement and fee-accounting assumptions remain background suspicion, but lower-confidence than the core oracle/accounting directions

## Useful Context
- The most stable audit picture still radiates from `ResupplyPairCore` plus the wrapper pair contract; external modules mostly amplify mistakes in accounting, pricing, or flow liveness
- A repeated cross-round pattern is state/accounting drift: the system can advance internal debt, share, collateral, or writeoff state in ways that do not cleanly match attributable debt or recoverable assets
- Redemption is not just a settlement path; it is a recurring place where borrower-specific writeoff state and global debt/share state can desynchronize
- Borrower checkpointing and reward claiming are not cleanly separated concerns: reward-side failures can propagate into core lending operations, so liveness matters alongside value correctness
- Low-confidence but retained background context includes redemption/liquidation handler ordering assumptions, fee handling, and bounded-integer debt edge cases for future correlation


## Latest Round Summary
# Round 5 Summary

## Agent: codex
- files touched: `src/protocol/pair/ResupplyPairCore.sol`, `src/protocol/ResupplyPair.sol`, `src/protocol/RewardDistributorMultiEpoch.sol`, `src/protocol/WriteOffToken.sol`, `src/interfaces/ICore.sol`
- files revisited / highest-attention files: `src/protocol/pair/ResupplyPairCore.sol` was the main focus, with repeated tracing around borrowing, redemption, liquidation, and reward-accounting paths; `src/protocol/RewardDistributorMultiEpoch.sol` was revisited for reward invalidation behavior
- main issue directions investigated: redemption write-off accounting, reward token invalidation effects, liquidation/redemption settlement assumptions around external handlers, constructor/runtime parameter consistency for max LTV
- promising but not retained directions: handler-trust concerns in `redeemCollateral()` and `liquidate()` were surfaced as draft findings (`F-014`, `F-015`) but were not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: this round’s attention was concentrated in the pair core and reward-distribution boundary, especially redemption accounting and max-LTV initialization
- notable differences in attention: only one agent contributed logs this round, so there was no cross-agent divergence
- underexplored but suspicious files/functions if clearly supported by the logs: external-handler settlement paths in `redeemCollateral()` and `liquidate()` were examined and flagged as plausible concerns in the draft output, but remain unretained in the current round state

## Retained Findings
- `F-013`: retained issue on reward-manager invalidation of the internal `redemptionWriteOff` token breaking redemption-loss accounting and later misallocating skipped write-offs
- `F-016`: retained issue on constructor-time `_maxLTV` assignment bypassing the cap enforced by the runtime setter, allowing unsafe over-100% LTV deployment states


Output only markdown.
