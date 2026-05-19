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
- files touched: `contracts/DecentralizedIndex.sol`, `contracts/TokenRewards.sol`, `contracts/WeightedIndex.sol`, `contracts/StakingPoolToken.sol`, plus scoped contract/interface tree for flow mapping
- files revisited / highest-attention files: `contracts/DecentralizedIndex.sol` was the main focus, with sustained attention on `contracts/TokenRewards.sol` and `contracts/WeightedIndex.sol`
- main issue directions investigated: permissionless fee liquidation and reward conversion timing/MEV, reward-swap slippage escalation leading to stuck rewards, `bond` rounding/undercollateralization risk, and permissionless rescue/sweep behavior
- promising but not retained directions: no separate non-retained direction is clearly evidenced in the visible codex log beyond the findings that were merged/retained

## Agent: opencode_1
- files touched: `contracts/DecentralizedIndex.sol`, `contracts/TokenRewards.sol`, `contracts/StakingPoolToken.sol`, `contracts/WeightedIndex.sol`, `contracts/interfaces/IDecentralizedIndex.sol`, `contracts/interfaces/ITokenRewards.sol`, `contracts/interfaces/IStakingPoolToken.sol`, `contracts/interfaces/IPEAS.sol`, `contracts/interfaces/IV3TwapUtilities.sol`, `contracts/interfaces/IUniswapV2Pair.sol`, `contracts/libraries/BokkyPooBahsDateTimeLibrary.sol`
- files revisited / highest-attention files: highest attention was on `contracts/DecentralizedIndex.sol` and `contracts/TokenRewards.sol`, with additional review of `contracts/StakingPoolToken.sol` and `contracts/WeightedIndex.sol`
- main issue directions investigated: `flash()`/reentrancy surfaces, `stake()` ordering and reentrancy, fee-on-transfer validation, oracle/pair-existence and TWAP assumptions, rescue/drain behavior, and reward-swap slippage/manipulation
- promising but not retained directions: `flash()` reentrancy, `stake()` mint-before-transfer/reentrancy, fee-on-transfer bonding validation, missing pair checks / price-query DoS, TWAP staleness/manipulation, and date/math edge cases were raised but not retained in the merged set

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `DecentralizedIndex.sol` and `TokenRewards.sol`, especially fee conversion, reward swap execution, and rescue-related flows
- notable differences in attention: `codex_1` was more concentrated on economic/MEV and `WeightedIndex.sol` bonding math, while `opencode_1` spread into `StakingPoolToken.sol`, `flash()` reentrancy, interfaces, oracle helpers, and the date library
- underexplored but suspicious files/functions if clearly supported by the logs: `DecentralizedIndex.sol::flash`, `StakingPoolToken.sol::stake`, and `WeightedIndex.sol` price/pair helper paths were examined but remain unretained and lightly corroborated in this round

## Retained Findings
- retained issues centered on swap-execution and accounting weaknesses: public fee liquidation with no min-out, sandwichable public reward conversion, unbounded slippage escalation that can brick reward swaps, possible per-asset rounding undercollateralization in `bond`, and permissionless sweeping of stray ETH / unsupported ERC20s to an external owner address


Output only markdown.
