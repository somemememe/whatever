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
- `src/protocol/pair/ResupplyPairCore.sol` / `src/protocol/ResupplyPair.sol` — enduring audit center for borrow/collateral/liquidation/redemption accounting, interest + exchange-rate refresh, debt booking, fee paths, external handler settlement, Convex transitions, and deployment/runtime parameter consistency
- Convex collateral management in `src/protocol/ResupplyPair.sol` — persistent risk surface where credited collateral can diverge from asset location across staking, pool-switch, migration, or sentinel/state transitions
- Oracle and rate-calculator integration around pair refresh/admin paths — protocol-wide dependency for price normalization, inversion/decimals handling, freshness/sanity assumptions, zero-price availability, and setter validity
- `src/protocol/RewardDistributorMultiEpoch.sol` with `src/dependencies/EpochTracker.sol` — recurring liveness/accounting boundary around checkpoint/integral/claim behavior, reward invalidation, and reward-token failure modes
- `src/protocol/WriteOffToken.sol` plus redemption/writeoff flows — durable dependency where token validity or borrower writeoff state affects loss attribution and remaining-collateral accounting
- `src/interfaces/ICore.sol`, `src/dependencies/CoreOwnable.sol`, `src/interfaces/IFeeDeposit.sol`, and initialization/admin setters — supporting governance/configuration surface for max-LTV, fee/mint-fee, oracle, and rate-calculator assumptions

## Issue Directions Seen
- Oracle math and refresh behavior remain a core direction: decimal mismatches, inversion logic, weak freshness/sanity assumptions, zero-price availability, and bad dependency addresses can break core flows
- Internal accounting vs real asset state is still the strongest recurring theme, especially where redemptions, writeoffs, migrations, fees, or external integrations let balances diverge from recoverable collateral
- Debt/interest accrual math remains firm: boundary or overflow behavior near numeric caps can skip, understate, or forgive elapsed debt growth
- Redemption/writeoff accounting remains a cross-round direction: borrower writeoff handling, skipped-loss tracking, debt-offset mechanics, and writeoff-token state can misallocate losses or misstate remaining collateral
- Reward distribution remains a recurring secondary direction: zero-borrow-share/integral edge cases can strand rewards, while reward invalidation or misbehaving reward tokens can break checkpointing/claims and trap balances
- Full-redemption/reset logic remains live: when debt is fully cleared, stale debt/share state can survive and contaminate later borrowing cycles
- Configuration enforcement is now a durable direction in both construction and live admin paths: unsafe parameter values or invalid external-module addresses can create overcharging states or brick pair operation

## Useful Context
- The stable audit picture still radiates from `ResupplyPairCore` plus the wrapper pair contract; external modules mostly amplify mistakes in accounting, pricing, liveness, or configuration enforcement
- A repeated cross-round pattern is state drift: internal debt, share, collateral, reward, or writeoff state can advance in ways that do not cleanly match attributable debt or recoverable assets
- Redemption is a recurring desynchronization point, not just a settlement path; borrower-specific writeoff state, debt-offset logic, reward-side behavior, and global debt/share cleanup can interact unexpectedly
- Governance/admin surfaces deserve the same scrutiny as arithmetic paths because constructor-time settings and live setters have both appeared able to evade safety assumptions or install invalid dependencies
- Low-confidence but retained background context includes handler ordering/trust assumptions, fee routing/deposit assumptions, and bounded-integer debt edge cases for future correlation


## Latest Round Summary
# Round 9 Summary

## Agent: codex
- files touched: `src/protocol/ResupplyPair.sol`, `src/protocol/pair/ResupplyPairCore.sol`, `src/protocol/RewardDistributorMultiEpoch.sol`, `src/protocol/WriteOffToken.sol`, `src/dependencies/CoreOwnable.sol`, `src/dependencies/EpochTracker.sol`, `src/libraries/VaultAccount.sol`, and interface files under `src/interfaces/`
- files revisited / highest-attention files: `src/protocol/pair/ResupplyPairCore.sol` and `src/protocol/ResupplyPair.sol`; follow-up attention also went to `src/dependencies/EpochTracker.sol`
- main issue directions investigated: pair accounting and borrow/repay edge cases; redemption and liquidation flow trust boundaries; Convex staking / pool configuration safety; fee-withdrawal epoch handling
- promising but not retained directions: external-handler trust concerns in `redeemCollateral` and `liquidate` were developed into candidate findings (`F-027`, `F-028`) in the agent output but were not retained after merge; a `forge build` attempt was also used for clues but crashed and did not contribute a retained issue

## Cross-Agent Status
- main overlap in file/area attention: only `codex` is present in this round; attention centered on `ResupplyPair.sol` and `ResupplyPairCore.sol`
- notable differences in attention: no cross-agent differences visible for this round
- underexplored but suspicious files/functions if clearly supported by the logs: `RewardDistributorMultiEpoch.sol` and `WriteOffToken.sol` were reviewed, but no retained findings from them are visible in this round’s merged output; handler-mediated redemption/liquidation paths in `ResupplyPairCore.sol` were investigated but remain unretained in current status

## Retained Findings
- retained issues focus on configuration and initialization hazards in the pair stack: unchecked Convex `pid` compatibility with collateral, an uncapped `minimumBorrowAmount` that can block partial deleveraging for existing borrowers, and zero `epochLength` bricking fee withdrawals
- all retained findings came from `codex` and primarily affect `ResupplyPair.sol`, `ResupplyPairCore.sol`, `EpochTracker.sol`, and `ICore.sol`


Output only markdown.
