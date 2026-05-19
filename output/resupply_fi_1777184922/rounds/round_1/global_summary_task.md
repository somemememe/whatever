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

## Agent: codex
- files touched: `src/protocol/pair/ResupplyPairCore.sol`, `src/protocol/ResupplyPair.sol`, `src/protocol/RewardDistributorMultiEpoch.sol`, `src/protocol/WriteOffToken.sol`, `src/interfaces/IOracle.sol`, plus broad file listing across `src/interfaces/*.sol`, `src/dependencies/*.sol`, and `src/libraries/VaultAccount.sol`
- files revisited / highest-attention files: `src/protocol/pair/ResupplyPairCore.sol` and `src/protocol/ResupplyPair.sol`; specific revisit points included oracle setup / exchange-rate logic and redemption / liquidation paths
- main issue directions investigated: oracle scaling and exchange-rate math; pair accounting and solvency flows; redemption / liquidation settlement assumptions; Convex staking integration behavior; reward / writeoff surface review
- promising but not retained directions: handler-trust / settlement verification in redemption and liquidation; stale share-scale interaction with `currentRateInfo.lastShares`; missing oracle zero/freshness/sanity checks

## Cross-Agent Status
- main overlap in file/area attention: single-agent round; attention concentrated on `ResupplyPairCore.sol` and `ResupplyPair.sol`
- notable differences in attention: no cross-agent differences in this round
- underexplored but suspicious files/functions if clearly supported by the logs: `src/protocol/RewardDistributorMultiEpoch.sol` and `src/protocol/WriteOffToken.sol` were read early but did not appear to receive the same depth of follow-up as the pair core / oracle / Convex paths

## Retained Findings
- retained high-severity issue on oracle integration: exchange-rate inversion ignores oracle-declared decimals, so non-18-decimal feeds can distort collateral pricing across borrow, solvency, redemption, and liquidation paths
- retained medium-severity issue on Convex integration: staking results are not checked before collateral crediting, which can leave collateral accounted as staked when it is not, later breaking exits or liquidations


Output only markdown.
