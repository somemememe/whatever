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
- `src/protocol/pair/ResupplyPairCore.sol` — primary accounting surface; redemption, solvency, checkpoint, and core balance-sheet paths drew the most scrutiny
- `src/protocol/ResupplyPair.sol` — wrapper/admin surface around pair behavior; oracle refresh and privileged setters looked relevant to systemic risk
- `src/protocol/RewardDistributorMultiEpoch.sol` — lazy reward distribution and checkpoint timing interacted with pair accounting, though early reward-sniping concerns were not retained
- `src/interfaces/IOracle.sol` — oracle output shape/assumptions matter materially for exchange-rate and solvency math
- `src/interfaces/IConvexStaking.sol` and related config surfaces — integration/config hooks were touched as lower-depth but potentially sensitive control points

## Issue Directions Seen
- Redemption/write-off accounting can diverge from real collateral state, especially around undercollateralized borrowers and hidden shortfall handling
- Oracle normalization remains a strong direction: inverted pricing, decimal mismatch, and zero/invalid values can distort solvency and redemption calculations
- Cross-contract accounting edges between pair core and reward checkpoint/distribution logic are a recurring review area, even where obvious sniping variants were not retained
- Privileged configuration paths (oracle, fee, swapper, convex pool) remain a standing direction because they influence accounting assumptions and external integrations
- Liquidation-related paths were noted as adjacent risk surfaces but received less depth than redemption/oracle logic

## Useful Context
- Audit attention has centered on accounting integrity rather than pure access control bugs
- The pair core is the main hub; wrapper/admin functions and reward distribution mostly matter through how they perturb core accounting
- Durable risk pattern so far: protocol state can look internally consistent while drifting from real collateral/value due to write-off or oracle-assumption errors
- Reward timing concerns were explored, but the more durable takeaway is checkpoint/accounting coupling rather than a specific retained sniping exploit


## Latest Round Summary
# Round 1 Summary

## Agent: codex
- files touched: `onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/ResupplyPair.sol`, `onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol`, `onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/RewardDistributorMultiEpoch.sol`; also enumerated the scoped Solidity tree
- files revisited / highest-attention files: `ResupplyPairCore.sol` received the deepest review; `RewardDistributorMultiEpoch.sol` and `ResupplyPair.sol` were repeatedly cross-checked against core accounting and migration behavior
- main issue directions investigated: redemption write-off accounting and borrower sync behavior; oracle exchange-rate assumptions and normalization; reward checkpoint / reward-token availability dependencies; Convex staking migration/accounting; interest accrual edge cases near debt-size limits
- promising but not retained directions: nearby redemption/accounting variants beyond the retained write-off findings; broader oracle-assumption issues around inverted pricing/invalid values; liquidation-adjacent risk surfaces; privileged configuration paths affecting accounting assumptions

## Cross-Agent Status
- main overlap in file/area attention: only one agent participated, with attention centered on pair accounting in `ResupplyPairCore.sol` and its integrations with `RewardDistributorMultiEpoch.sol` and `ResupplyPair.sol`
- notable differences in attention: no cross-agent differences this round
- underexplored but suspicious files/functions if clearly supported by the logs: liquidation-related paths were noted as adjacent risk surfaces but were less deeply explored than redemption, oracle, reward-checkpoint, and Convex migration logic

## Retained Findings
- retained findings focused on accounting drift and availability failures: discarded redemption write-off shortfalls on undercollateralized borrowers, invalidation of the internal write-off reward disabling loss socialization, Convex pool migration hiding live collateral, reward-hook / reward-token reverts bricking checkpointed operations, oracle inversion without decimal/zero handling, and interest accrual silently skipping overflowed periods


Output only markdown.
