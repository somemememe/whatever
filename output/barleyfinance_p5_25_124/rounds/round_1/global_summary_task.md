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
- files touched: `contracts/DecentralizedIndex.sol`, `contracts/WeightedIndex.sol`, `contracts/TokenRewards.sol`, `contracts/StakingPoolToken.sol`, plus contract interface inventory under `contracts/interfaces/`
- files revisited / highest-attention files: `contracts/TokenRewards.sol`, `contracts/DecentralizedIndex.sol`, `contracts/WeightedIndex.sol`, `contracts/StakingPoolToken.sol`
- main issue directions investigated: referral initialization and referral-setting trust boundaries; third-party claiming on behalf of users; reward swap/slippage arithmetic in `TokenRewards`; transfer-hook fee-swap edge cases in `DecentralizedIndex`; mint-before-payment / reentrancy exposure in `WeightedIndex.bond()`
- promising but not retained directions: `WeightedIndex.bond()` malicious-asset reentrancy / undercollateralization path

## Agent: opencode_1
- files touched: `contracts/DecentralizedIndex.sol`, `contracts/TokenRewards.sol`, `contracts/WeightedIndex.sol`, `contracts/StakingPoolToken.sol`, `contracts/interfaces/IDecentralizedIndex.sol`, `contracts/interfaces/ITokenRewards.sol`, `contracts/interfaces/IReferral.sol`
- files revisited / highest-attention files: `contracts/DecentralizedIndex.sol`, `contracts/TokenRewards.sol`, `contracts/WeightedIndex.sol`, `contracts/StakingPoolToken.sol`
- main issue directions investigated: unrestricted rescue/admin surfaces; staking-pool transfer restrictions; constructor/config validation; flash-loan / callback / price-manipulation angles in index pricing; referral initialization; swap slippage and arithmetic safety
- promising but not retained directions: unrestricted rescue of protocol assets; stake-transfer restriction bypass; flash-loan-driven price manipulation / callback reentrancy; decimals / overflow / zero-address deployment concerns

## Cross-Agent Status
- main overlap in file/area attention: both agents centered on `TokenRewards.sol`, `DecentralizedIndex.sol`, `WeightedIndex.sol`, and `StakingPoolToken.sol`, with strongest overlap around referral handling in `TokenRewards`
- notable differences in attention: `codex_1` focused more on reward-claim flows, fee-swap liveness, and bond/debond state ordering; `opencode_1` spent more attention on admin/rescue functions, constructor validation, and flash-loan / pricing manipulation themes
- underexplored but suspicious files/functions if clearly supported by the logs: `WeightedIndex.bond()` remained a live attention point from `codex_1`, but was not retained after merge; `DecentralizedIndex` rescue/flash paths were examined by `opencode_1` but not retained

## Retained Findings
- `TokenRewards.updateReferral()` first-time initialization was retained as the round’s main critical issue: an arbitrary first caller can seize referral control and then redirect or break reward-dependent flows, with `StakingPoolToken` share updates amplifying the impact
- `TokenRewards.claimReward(address _wallet, address _referrer)` was retained for allowing third parties to front-run a victim’s first claim and permanently bind attacker-controlled referrers
- `DecentralizedIndex` transfer-hook fee logic was retained for a dust-supply liveness failure where `_feeSwap(0)` can freeze residual transfers/sells
- `TokenRewards` reward-swap slippage accumulation was retained as a lower-confidence arithmetic/liveness issue that can strand DAI fees after repeated failed swaps


Output only markdown.
