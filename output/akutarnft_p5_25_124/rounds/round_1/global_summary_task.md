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
- files touched: `onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol`
- files revisited / highest-attention files: same contract, especially the auction/refund section around bid tracking, `processRefunds()`, `emergencyWithdraw()`, and `claimProjectFunds()`
- main issue directions investigated: bidder-record vs NFT-count accounting, refund processing liveness, refund transfer failure as a settlement blocker, emergency withdrawal conditions, and zero-amount bid effects on settlement progress
- promising but not retained directions: no separate non-retained direction is clearly evidenced in the log beyond the retained set

## Agent: opencode_1
- files touched: `onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol`
- files revisited / highest-attention files: same contract; attention clustered around `_bid()`, `processRefunds()`, `emergencyWithdraw()`, `claimProjectFunds()`, and owner-controlled NFT contract wiring
- main issue directions investigated: reentrancy on refund/withdraw paths, refund arithmetic behavior, refund-progress withdrawal gating, owner control over NFT contract checks, and auction-ending / bid-ordering edge cases
- promising but not retained directions: reentrancy claims on `_bid()`, `processRefunds()`, and `emergencyWithdraw()`; owner-manipulated NFT contract checks; timing/front-running concerns; one overlap on the withdrawal-gate logic was retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on the sole in-scope contract and heavily overlapped on the refund-settlement / `claimProjectFunds()` area
- notable differences in attention: `codex_1` focused on accounting mismatches, refund DoS, emergency refund semantics, and zero-bid dummy records; `opencode_1` focused more on reentrancy-style hypotheses, owner-controlled external contract checks, and auction timing behavior
- underexplored but suspicious files/functions if clearly supported by the logs: no additional files were in scope; within the contract, `_bid()` and `setNFTContract()` were flagged by `opencode_1` but not retained this round

## Retained Findings
- refund settlement progress is compared against total NFTs sold rather than bidder-record progress, which can permanently lock project proceeds
- a bidder that reverts on ETH receipt can permanently stall `processRefunds()` and block later settlement
- `emergencyWithdraw()` can repay a bidder even after NFT delivery if their record remains unprocessed
- `bid(0)` can create dummy bidder records that let the withdrawal gate appear satisfied before all real refunds are processed


Output only markdown.
