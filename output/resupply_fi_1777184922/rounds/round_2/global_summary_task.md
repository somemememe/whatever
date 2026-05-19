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
- `src/protocol/pair/ResupplyPairCore.sol` / `src/protocol/ResupplyPair.sol` — main audit center; collateral pricing, solvency accounting, redemption, liquidation, and Convex-staking state transitions
- Oracle integration around `src/interfaces/IOracle.sol` — exchange-rate scaling/decimal handling is a durable risk surface affecting multiple pair flows
- Convex collateral path in pair contracts — external staking success assumptions can desync credited collateral from real staked assets
- `src/protocol/RewardDistributorMultiEpoch.sol` / `src/protocol/WriteOffToken.sol` — reviewed but comparatively underexplored versus pair/oracle paths
- Supporting interfaces, dependencies, and `src/libraries/VaultAccount.sol` — background context for pair accounting and vault state

## Issue Directions Seen
- Oracle normalization and exchange-rate math remain a core direction, especially decimal mismatches, inversion logic, and missing freshness/sanity guards
- Pair accounting vs real asset state is a recurring theme, particularly where external integrations or delayed state updates can break solvency assumptions
- Redemption and liquidation flows look sensitive to handler/settlement trust assumptions and to how exchange-rate state is carried forward
- Convex integration is a live direction: collateral can be credited on assumed staking outcomes rather than verified outcomes
- Reward/writeoff components remain secondary but potentially worthwhile follow-up surfaces because they received lighter depth

## Useful Context
- Audit attention has been concentrated on the pair core and wrapper pair contract; most durable observations so far radiate from those flows
- One retained issue already links oracle-decimal mishandling to borrow, solvency, redemption, and liquidation behavior, making oracle integration a cross-cutting dependency rather than an isolated bug
- Another retained issue shows external staking assumptions can create accounting/reality divergence, reinforcing a broader theme of unchecked downstream effects
- Early suspicious but not retained observations included stale share-scale interactions and missing oracle zero/freshness checks, which still help frame follow-up review even without separate findings


## Latest Round Summary
# Round 2 Summary

## Agent: codex
- files touched: `src/protocol/pair/ResupplyPairCore.sol`, `src/protocol/RewardDistributorMultiEpoch.sol`, `src/protocol/ResupplyPair.sol`
- files revisited / highest-attention files: highest attention on `ResupplyPairCore.sol`; repeated focus on reward accounting in `RewardDistributorMultiEpoch.sol` and Convex staking/accounting in `ResupplyPair.sol`
- main issue directions investigated: core accounting paths; reward checkpoint/integral behavior during zero-borrow-share periods; Convex pool migration and collateral location/accounting mismatches; some redemption/fee-flow validation
- promising but not retained directions: low-confidence redemption fee double-counting around `redeemCollateral` / `withdrawFees` and external handler burn semantics was explored but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: single-agent round, so overlap is concentrated in the pair core, reward distributor, and Convex pool-management paths
- notable differences in attention: not applicable beyond codex’s split between reward-accounting analysis and Convex migration/accounting analysis
- underexplored but suspicious files/functions if clearly supported by the logs: redemption fee handling around `src/protocol/pair/ResupplyPairCore.sol` (`redeemCollateral`, `withdrawFees`) and `src/protocol/ResupplyPair.sol` handler interaction was examined but remained unretained/low-confidence in this round

## Retained Findings
- rewards claimed while `totalBorrow.shares == 0` can become permanently stranded because reward balances are marked as accounted without advancing distributable integrals
- Convex pool migration mishandles the sentinel `pid == 0`, creating accounting-location mismatches that can orphan/live-lock collateral at the protocol level


Output only markdown.
