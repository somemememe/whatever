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
- files touched: all 16 in-scope Solidity files were enumerated; detailed reads centered on `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol`, with targeted attention to `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Access/MISOAdminAccess.sol` and `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Utils/BoringBatchable.sol`
- files revisited / highest-attention files: `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol` was reviewed in multiple chunks and via targeted grep; highest-attention areas were `initAuction`/`initMarket`, `commitEth`, `commitTokensFrom`, `withdrawTokens`, `cancelAuction`, `finalize`, and `setAuctionWallet`
- main issue directions investigated: batched ETH commitment accounting through `BoringBatchable`; first-caller initialization/admin takeover risk; collateralization/accounting mismatches from nominal vs actual token receipts during funding and ERC20 bidding
- promising but not retained directions: an extra pass looked for additional distinct collateralization/settlement flaws, but no extra merged finding beyond the retained accounting issue is visible in the logs

## Agent: opencode_1
- files touched: read all 16 in-scope Solidity files, with findings focused on `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol`; supporting attention also went to `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Access/MISOAdminAccess.sol`, `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Utils/SafeTransfer.sol`, `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Utils/BoringBatchable.sol`, and `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/interfaces/IERC20.sol`
- files revisited / highest-attention files: `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol` was the clear highest-attention file; reported hotspots included initialization, `setAuctionWallet`, reentrancy-exposed functions, price math, and finalization
- main issue directions investigated: public initialization takeover; wallet redirection after commitments; reentrancy coverage gaps; price/division-by-zero behavior; ETH transfer mechanics and interface/configuration mismatches
- promising but not retained directions: reentrancy inconsistency, zero-price math reverts, `.transfer()` gas-stipend concerns, point list validation, permit compatibility, finalize caller/comment mismatches, and compiler-version age were raised but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol`, especially initialization/admin control and proceeds-routing logic; both also touched `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Access/MISOAdminAccess.sol`
- notable differences in attention: `codex_1` went deeper on batching and token-accounting/collateralization via `BoringBatchable` and funding/bid accounting paths; `opencode_1` explored a broader set of secondary hypotheses around reentrancy coverage, math edge cases, transfer mechanics, and interface assumptions
- underexplored but suspicious files/functions if clearly supported by the logs: `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Utils/SafeTransfer.sol` and `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/interfaces/IERC20.sol` were flagged by `opencode_1` but did not survive merge; current retained attention still centers more heavily on `DutchAuction.sol` than those helpers

## Retained Findings
- retained issues from this round are: batched `commitEth()` reuse of one `msg.value` across delegatecalled subcalls; public first-caller initialization takeover of uninitialized auctions and admin/proceeds control; nominal-vs-actual token accounting that can undercollateralize auctions with non-standard ERC20s; and post-commitment wallet redirection by the admin via `setAuctionWallet()`


Output only markdown.
