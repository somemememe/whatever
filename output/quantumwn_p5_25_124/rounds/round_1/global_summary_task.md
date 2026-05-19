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
- files touched: `contracts/Staking.sol`, `contracts/interface/IDistributor.sol`, `contracts/interface/IsQWA.sol`, `@openzeppelin/contracts/token/ERC20/IERC20.sol`, `@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol`, `@openzeppelin/contracts/utils/Context.sol`
- files revisited / highest-attention files: `contracts/Staking.sol` was the clear focus; local token/distributor interfaces were used for call-surface context
- main issue directions investigated: unchecked ERC20 return values in `stake()`/`unstake()`, missed-epoch catch-up behavior in `rebase()`, just-in-time staking around predictable epoch boundaries, nominal-vs-actual token accounting for deflationary/fee-on-transfer behavior, overdue-epoch view behavior
- promising but not retained directions: `secondsToNextEpoch()` underflow/revert when an epoch is overdue

## Agent: opencode_1
- files touched: `contracts/Staking.sol`, `contracts/interface/IsQWA.sol`, `contracts/interface/IDistributor.sol`
- files revisited / highest-attention files: `contracts/Staking.sol`
- main issue directions investigated: constructor and `setDistributor()` zero-address validation, reentrancy on `stake()`, `unstake()` behavior when rebasing, public `rebase()` / MEV angle, staking to arbitrary recipient addresses, missing events, epoch arithmetic overflow
- promising but not retained directions: zero-address validation, reentrancy, public-rebase/MEV, arbitrary-recipient staking, missing event emission, arithmetic overflow

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `contracts/Staking.sol`, especially the `stake()`, `unstake()`, and `rebase()` flow
- notable differences in attention: `codex_1` focused on token-transfer semantics and reward-accounting/economic extraction paths; `opencode_1` focused more on validation, access/control-surface, and generic reentrancy/MEV hypotheses
- underexplored but suspicious files/functions if clearly supported by the logs: attention was heavily concentrated on `stake()/unstake()/rebase()`, with `setDistributor()` and `secondsToNextEpoch()` receiving comparatively lighter retained attention

## Retained Findings
- retained issues centered on `Staking.sol` only: unchecked ERC20 boolean returns in stake/unstake, single-epoch catch-up in `rebase()` enabling backlog capture by late entrants, predictable epoch-boundary reward sniping, and nominal-amount accounting that can undercollateralize the pool if QWA short-transfers or charges transfer fees


Output only markdown.
