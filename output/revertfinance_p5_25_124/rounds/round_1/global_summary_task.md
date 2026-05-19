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
- files touched: `onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol`; directory structure under `onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/`
- files revisited / highest-attention files: `V3Utils.sol` was the clear focus
- main issue directions investigated: callback authorization around `execute()` / `onERC721Received`; external-call and swap-router control in `_swap`; approval / token-flow handling around mint and liquidity add paths
- promising but not retained directions: no separate non-retained line of inquiry is clearly logged beyond general interface/context review

## Agent: opencode_1
- files touched: `onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol`; `onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/lib/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol`; broad directory listings under `lib/`
- files revisited / highest-attention files: `V3Utils.sol` was the main target; `INonfungiblePositionManager.sol` was supporting context
- main issue directions investigated: public entrypoint access control in `swapAndMint`, `swapAndIncreaseLiquidity`, and `execute`; callback-driven forced execution; swap parameter / validation issues
- promising but not retained directions: unrestricted public mint / liquidity-add framing, zero-amount swap handling, deadline / recipient / slippage validation gaps, and low-severity observability / griefing themes were raised but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `V3Utils.sol`, especially the `execute()` / `onERC721Received` path and approval-driven position handling
- notable differences in attention: `codex_1` went deeper on `_swap` arbitrary-call behavior and residual ERC20 approvals; `opencode_1` spent more attention on broad public-entrypoint and validation concerns
- underexplored but suspicious files/functions if clearly supported by the logs: review depth was heavily concentrated in `V3Utils.sol`; the `lib/` interfaces and libraries appear mostly contextual, and `swapAndMint` / `swapAndIncreaseLiquidity` received less merged support than the callback and swap internals

## Retained Findings
- retained issues center on `V3Utils.sol` trust boundaries: approved NFT operators can force callback execution and drain withdrawable value, user-supplied `swapData` acts as an arbitrary-call surface while the contract temporarily owns a position, and leftover position-manager allowances can brick zero-first ERC20 flows across the deployment


Output only markdown.
