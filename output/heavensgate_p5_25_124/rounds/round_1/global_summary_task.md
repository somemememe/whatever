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
- files touched: `contracts/Staking.sol`, `contracts/interface/IsHATE.sol`, `contracts/interface/IDistributor.sol`; also enumerated the in-scope Solidity files
- files revisited / highest-attention files: `contracts/Staking.sol`
- main issue directions investigated: `stake()` / `rebase()` ordering, `epoch.distribute` accounting, multi-epoch lag behavior in `rebase()`, raw ERC20 transfer semantics in `stake()` and `unstake()`
- promising but not retained directions: no clearly separate unretained line of inquiry is visible in the log

## Agent: opencode_1
- files touched: `contracts/Staking.sol`, `contracts/interface/IDistributor.sol`, `contracts/interface/IsHATE.sol`, `@openzeppelin/contracts/access/Ownable.sol`, `@openzeppelin/contracts/token/ERC20/IERC20.sol`
- files revisited / highest-attention files: `contracts/Staking.sol`
- main issue directions investigated: unchecked ERC20 return handling in `stake()` / `unstake()`, reentrancy, slippage/front-running framing, distributor configuration, unstake balance-check ordering, timestamp dependence
- promising but not retained directions: reentrancy on token callbacks, slippage/sandwich concerns, `setDistributor()` validation / zero-address concerns, unstake race-condition framing, timestamp manipulation

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `contracts/Staking.sol`, especially token transfer handling around `stake()` and `unstake()`
- notable differences in attention: `codex_1` focused on rebase accounting and insolvency paths tied to expired or lagged epochs; `opencode_1` focused more on generic ERC20 integration and auxiliary risk themes
- underexplored but suspicious files/functions if clearly supported by the logs: `setDistributor()` / `distributor.distribute()` received some attention from `opencode_1` but did not produce a retained issue; interfaces and OpenZeppelin files were mostly contextual reads

## Retained Findings
- Retained issues center on `Staking.sol` accounting and token interaction assumptions.
- Two retained findings came from `codex_1` on rebase-time misaccounting: post-expiry stakes can be misclassified as rewards, and the effect can be realized immediately when the contract is multiple epochs behind.
- One retained finding, supported by both agents, is that raw ERC20 interactions assume strict full-transfer / reverting semantics, creating insolvency or user-loss risk with non-standard tokens.


Output only markdown.
