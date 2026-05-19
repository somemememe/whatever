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
- `src/protocol/pair/ResupplyPairCore.sol` / `src/protocol/ResupplyPair.sol` — persistent audit center; solvency/accounting, redemption/liquidation, fee paths, and Convex staking or migration state transitions
- Convex collateral management in `src/protocol/ResupplyPair.sol` — durable risk surface for credited-collateral vs actual asset location, including pool-switch/migration edge cases
- Oracle integration around `src/interfaces/IOracle.sol` — exchange-rate normalization, decimals, inversion, and sanity/freshness handling remain cross-cutting dependencies
- `src/protocol/RewardDistributorMultiEpoch.sol` — now a meaningful surface; reward checkpoint/integral behavior can fail in zero-borrow-share states and strand rewards
- `src/protocol/WriteOffToken.sol` / `src/libraries/VaultAccount.sol` and supporting interfaces — background context for accounting/state flow, but lower centrality than pair/oracle/reward paths

## Issue Directions Seen
- Oracle normalization and exchange-rate math remain a core direction, especially decimal mismatches, inversion logic, and weak freshness/sanity assumptions
- Pair accounting vs real asset state is a recurring theme, particularly when external integrations, migrations, or delayed updates let internal balances diverge from actual collateral location
- Convex integration remains live beyond simple staking-success assumptions: pool-management edge cases and sentinel/state encoding can orphan or live-lock collateral
- Reward distribution has emerged as a concrete direction: integral/checkpoint accounting around `totalBorrow.shares == 0` can mark rewards as handled without making them claimable
- Redemption/liquidation flows continue to look sensitive to handler/settlement assumptions and fee-accounting edge cases, though some fee-path suspicions remain low-confidence

## Useful Context
- Most durable observations still radiate from the pair core plus wrapper pair contract; external dependencies amplify accounting mistakes rather than isolate them
- A retained oracle-related theme already ties pricing math to borrow, solvency, redemption, and liquidation behavior, making oracle handling a protocol-wide dependency
- Another retained theme is accounting/location divergence: both Convex staking assumptions and later pool-migration behavior show the protocol can mis-credit collateral relative to where assets actually sit
- Reward accounting is no longer just a secondary follow-up area; zero-borrow-share periods exposed a durable pattern where state can advance “accounted” balances without preserving user-distributable value
- Low-confidence but recurring context includes redemption fee handling around `redeemCollateral` / `withdrawFees` and related handler burn semantics, useful as background but not yet a stable finding direction


## Latest Round Summary
# Round 3 Summary

## Agent: codex
- files touched: `src/protocol/pair/ResupplyPairCore.sol`, `src/protocol/ResupplyPair.sol`, `src/protocol/RewardDistributorMultiEpoch.sol`, `src/protocol/WriteOffToken.sol`, plus interface listing via file map
- files revisited / highest-attention files: strongest focus on `src/protocol/pair/ResupplyPairCore.sol`; secondary focus on `src/protocol/RewardDistributorMultiEpoch.sol` and `src/protocol/ResupplyPair.sol`
- main issue directions investigated: core lending state flows; solvency/checkpoint paths; reward-claim coupling into borrow/repay/liquidation; exchange-rate/oracle refresh paths; redemption/share-refactor accounting
- promising but not retained directions: `uint128` interest-overflow debt forgiveness (`F-006` in raw output) and handler-trust around redemption/liquidation burn assumptions (`F-008` in raw output)

## Cross-Agent Status
- main overlap in file/area attention: this round only shows `codex`; attention centered on `ResupplyPairCore` with supporting review of reward distribution logic
- notable differences in attention: no cross-agent differences visible in the logs for this round
- underexplored but suspicious files/functions if clearly supported by the logs: `src/protocol/WriteOffToken.sol` was opened early but does not show continued attention; redemption/liquidation handler interactions in `ResupplyPairCore` were examined but not retained after merge

## Retained Findings
- reward claiming remains tightly coupled to borrower checkpointing, so external reward-claim reverts can block borrow, repayment, collateral withdrawal, and liquidation flows
- zero oracle prices remain a critical availability risk because exchange-rate refresh divides by the returned price without a zero guard
- share-refactor rounding remains retained as a low-severity accounting issue where lazy per-user floor division can leave small debt amounts effectively unowned


Output only markdown.
