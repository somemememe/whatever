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
- `src/protocol/pair/ResupplyPairCore.sol` / `src/protocol/ResupplyPair.sol` — enduring audit center for borrow/collateral/liquidation/redemption accounting, solvency + exchange-rate refresh, interest accrual edge cases, fee paths, external handler settlement, Convex transitions, and deployment/runtime parameter consistency
- Convex collateral management in `src/protocol/ResupplyPair.sol` — persistent risk surface where credited collateral can diverge from asset location across staking, pool-switch, migration, or sentinel/state transitions
- Oracle integration around `src/interfaces/IOracle.sol` and pair refresh paths — protocol-wide dependency for price normalization, inversion/decimals handling, freshness/sanity assumptions, and zero-price availability
- `src/protocol/RewardDistributorMultiEpoch.sol` — recurring liveness/accounting boundary; checkpoint/integral/claim behavior, reward invalidation, and reward-token failures can strand balances or spill into borrower-facing pair flows
- `src/protocol/WriteOffToken.sol` — durable writeoff/redemption accounting dependency, especially where token state or validity affects loss attribution
- `src/interfaces/ICore.sol` and pair initialization paths — supporting scope for governance/risk-parameter assumptions, especially max-LTV and fee-cap bounds at construction vs runtime
- `src/libraries/VaultAccount.sol` — supporting accounting primitive revisited around debt/share state transitions, accrual math boundaries, and full-reset cleanup behavior

## Issue Directions Seen
- Oracle math and refresh behavior remain a core direction: decimal mismatches, inversion logic, weak freshness/sanity assumptions, and zero-price availability failures
- Internal accounting vs real asset state is still the strongest recurring theme, especially where redemptions, writeoffs, migrations, or external integrations let balances diverge from recoverable collateral
- Debt/interest accrual math is now a firmer direction: boundary or overflow behavior near numeric caps can skip, understate, or forgive elapsed debt growth
- Redemption/writeoff accounting remains a firm cross-round direction: borrower writeoff handling, skipped-loss tracking, and writeoff-token state can misallocate losses or misstate remaining collateral
- Reward distribution remains a recurring secondary direction in two forms: zero-borrow-share/integral edge cases can strand rewards, and reward invalidation or misbehaving reward tokens can break checkpointing/claims and trap already-accrued or pair-held balances
- Full-redemption/reset logic remains live: when debt is fully cleared, stale debt/share state can survive and contaminate later borrowing cycles
- Convex integration remains live beyond staking-success assumptions: pool-management edge cases and state encoding can orphan or live-lock collateral
- Configuration-bound enforcement is now a durable direction: constructor-time assignments can bypass runtime setter guards, creating unsafe deployment states such as over-cap LTV or fees

## Useful Context
- The most stable audit picture still radiates from `ResupplyPairCore` plus the wrapper pair contract; external modules mostly amplify mistakes in accounting, pricing, liveness, or configuration enforcement
- A repeated cross-round pattern is state drift: internal debt, share, collateral, reward, or writeoff state can advance in ways that do not cleanly match attributable debt or recoverable assets
- Redemption is a recurring desynchronization point, not just a settlement path; borrower-specific writeoff state, reward-side behavior, and global debt/share cleanup can interact unexpectedly
- Reward-side components are not isolated from core lending behavior: checkpointing, claiming, invalidation, or reward-token misbehavior can affect both value accounting and operational liveness
- Initialization deserves the same scrutiny as live admin paths because constructor-set parameters have repeatedly appeared able to evade runtime safety bounds
- Low-confidence but retained background context includes handler ordering/trust assumptions, fee handling, and bounded-integer debt edge cases for future correlation


## Latest Round Summary
# Round 8 Summary

## Agent: codex
- files touched: `src/protocol/pair/ResupplyPairCore.sol`, `src/protocol/ResupplyPair.sol`, `src/protocol/RewardDistributorMultiEpoch.sol`, `src/protocol/WriteOffToken.sol`, `src/libraries/VaultAccount.sol`, `src/dependencies/CoreOwnable.sol`, `src/dependencies/EpochTracker.sol`, `src/interfaces/IFeeDeposit.sol`
- files revisited / highest-attention files: `src/protocol/pair/ResupplyPairCore.sol` and `src/protocol/ResupplyPair.sol` dominated review, especially borrow, interest/exchange-rate update, redemption, and liquidation paths
- main issue directions investigated: pair accounting invariants; borrow/mint-fee debt booking; setter-driven configuration safety for oracle and rate calculator; redemption/liquidation debt-offset mechanics; reward/distributor surface as adjacent context
- promising but not retained directions: a handler-trust issue around `redeemCollateral()` / `liquidate()` and off-pair debt burning was reported by the agent as `F-024`, but it was not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: only `codex` is present in this round; attention centered on `ResupplyPairCore.sol` and `ResupplyPair.sol`
- notable differences in attention: no cross-agent differences are visible from this round’s logs
- underexplored but suspicious files/functions if clearly supported by the logs: `RewardDistributorMultiEpoch.sol` and the redemption/liquidation handler interaction paths were inspected but did not produce retained findings in the merged round state

## Retained Findings
- `F-025`: retained the uncapped `mintFee` issue, where governance/configuration can make new borrows immediately overcharged relative to tokens received
- `F-026`: retained the invalid-address setter issue, where `setOracle()` / `setRateCalculator()` can point to zero or non-contract addresses and brick core pair flows


Output only markdown.
