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
- files touched: broad pass across both code copies, with explicit attention on `contracts/Curve.sol`, `contracts/ProportionalLiquidity.sol`, `contracts/Swaps.sol`, `contracts/Assimilators.sol`, `contracts/CurveFactory.sol`, `contracts/Orchestrator.sol`, and `contracts/interfaces/ICurveFactory.sol`
- files revisited / highest-attention files: `Curve.sol`, `ProportionalLiquidity.sol`, `Swaps.sol`, `Assimilators.sol`, `CurveFactory.sol`; analysis was mirrored across both duplicated deployment directories
- main issue directions investigated: flash-loan callback reentrancy into deposit / LP minting, factory-to-swap integration breakage around fee getters, delegatecall risk from externally supplied assimilators, and whitelist-era LP withdrawal behavior after transfer
- promising but not retained directions: early note that zero `epsilon` could make the flash path cheaper initially, but this was folded into the main flash-loan issue rather than kept separately

## Agent: opencode_1
- files touched: read-focused pass over `contracts/Curve.sol`, `contracts/Swaps.sol`, `contracts/ProportionalLiquidity.sol`, `contracts/Storage.sol`, `contracts/CurveMath.sol`, `contracts/Orchestrator.sol`, `contracts/Assimilators.sol`, `contracts/CurveFactory.sol`, `contracts/Structs.sol`, `contracts/ViewLiquidity.sol`, `contracts/MerkleProver.sol`, `contracts/interfaces/IFlashCallback.sol`, `contracts/interfaces/IAssimilator.sol`, plus one duplicate `Curve.sol` and part of `contracts/lib/ABDKMath64x64.sol`
- files revisited / highest-attention files: strongest visible concentration on `Curve.sol`, `Swaps.sol`, `ProportionalLiquidity.sol`, `Orchestrator.sol`, `Assimilators.sol`, and `CurveFactory.sol`
- main issue directions investigated: delegatecall-based assimilator trust, flash-loan callback safety, whitelist withdrawal edge cases, owner/parameter control surfaces, approvals in orchestrator setup, and several configuration / edge-case DoS ideas
- promising but not retained directions: unlimited approval in `Orchestrator.sol`, owner freeze / parameter abuse, division-by-zero withdrawal edge case, flash fees routed to owner, oracle dependency concerns, immutable merkle root, deadline comparator strictness, and duplicate-pool factory concerns

## Cross-Agent Status
- main overlap in file/area attention: both agents converged on `Curve.sol`, `ProportionalLiquidity.sol`, `Assimilators.sol`, `CurveFactory.sol`, and swap/liquidity paths; both independently surfaced the flash-loan reentrancy mint issue and the assimilator `delegatecall` trust boundary
- notable differences in attention: `codex_1` was more focused on cross-contract exploitability and duplicate deployment parity, while `opencode_1` explored a wider set of control, configuration, and edge-case hypotheses that mostly were not retained
- underexplored but suspicious files/functions if clearly supported by the logs: `Orchestrator.sol` and `Storage.sol` received some attention, but only assimilator wiring from `Orchestrator.sol` contributed to retained findings; `CurveMath.sol` and `ABDKMath64x64.sol` were read without any retained issue emerging from this round

## Retained Findings
- flash-loan callback can reenter deposits during temporarily drained balances and mint inflated LP shares, creating a direct pool-drain path
- factory-created curves point swaps at a factory address that lacks the required fee getter interface, causing swap execution to revert
- externally supplied assimilators execute through `delegatecall`, so an unsafe or upgradeable assimilator can seize pool storage and assets
- LP tokens transferred during the whitelist stage can become temporarily non-withdrawable because withdrawal accounting is tied to the original depositor rather than current holder


Output only markdown.
