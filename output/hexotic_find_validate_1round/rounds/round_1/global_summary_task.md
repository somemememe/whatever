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
- `hex-otc.sol` — primary audit surface so far; attention centers on order lifecycle, escrow bookkeeping, settlement, and cancellation paths
- Order flow: `offerETH()`, `offerHEX()`, `make()`, `newOffer()` — order ID creation/propagation is a key direction
- Settlement/refund flow: `buyHEX()`, `buyETH()`, `cancel()` — ETH payout/refund behavior drew review, especially around transfer-based delivery
- `FlawVerifier.sol` — scanned but still comparatively underexplored despite being large
- `Contract.sol` — appeared structurally anomalous in logs and may merit context clarification if revisited
- Supporting libs: `erc20.sol`, `math.sol` — touched as dependencies, not primary issue centers yet

## Issue Directions Seen
- Order identifier/accounting mismatches in the OTC flow are the clearest recurring direction, especially where returned IDs, emitted IDs, and stored order slots may diverge
- Order lifecycle correctness in `hex-otc.sol` remains the dominant theme: creation, fill, and cancel paths are all coupled through shared escrow/state assumptions
- ETH transfer semantics in settlement/cancel paths were considered as a griefing/bricking direction, but are not currently a retained cross-round issue

## Useful Context
- Audit attention is heavily concentrated in `hex-otc.sol`; the strongest current signal is around state propagation rather than token math
- The retained finding establishes a concrete pattern: externally surfaced order metadata can disagree with the actual persisted order state
- No multi-agent divergence exists yet, so current memory mainly reflects a single focused pass
- Large or unusual files (`FlawVerifier.sol`, `Contract.sol`) have weak coverage relative to their apparent complexity or anomalies


## Latest Round Summary
# Round 1 Summary

## Agent: codex
- files touched: `hex-otc.sol`, `FlawVerifier.sol`, `erc20.sol`, `math.sol`, `Contract.sol`; also briefly consulted `global_summary.md`
- files revisited / highest-attention files: `hex-otc.sol` was the clear focus; `FlawVerifier.sol` received secondary pattern scans and spot review
- main issue directions investigated: order lifecycle and ID propagation in `offerETH()` / `offerHEX()` / `make()` / `newOffer()`; fill/cancel settlement paths using ETH `transfer`; verifier/helper swap behavior in `FlawVerifier.sol`
- promising but not retained directions: sandwich/slippage exposure from zero-`amountOutMin` swaps in `FlawVerifier.sol`; general suspicion around the large but lightly explored `FlawVerifier.sol` and the anomalous `Contract.sol`

## Cross-Agent Status
- main overlap in file/area attention: single-agent round, so overlap is limited to codex’s concentration on `hex-otc.sol` order creation, settlement, and cancellation
- notable differences in attention: no cross-agent divergence in this round
- underexplored but suspicious files/functions if clearly supported by the logs: `FlawVerifier.sol` remained comparatively underexplored despite its size and helper/exploit flow surface; `Contract.sol` appeared structurally unusual in the logs but was not meaningfully analyzed

## Retained Findings
- order creation in `hex-otc.sol` can surface `0` instead of the real live order ID, leaving makers/integrators with the wrong identifier while the actual order remains active and fillable
- ETH payout/refund paths in `buyHEX()`, `buyETH()`, and `cancel()` rely on Solidity `transfer`, so some contract-based participants can experience unfillable orders or failed cancellations due to recipient-side gas/payability limits


Output only markdown.
