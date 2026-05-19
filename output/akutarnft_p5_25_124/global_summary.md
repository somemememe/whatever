# Global Audit Memory

## Scope Touched
- `onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol` — audit attention stays concentrated on auction settlement, bidder/refund bookkeeping, and proceeds-withdrawal gating
- Refund and payout flow around `_bid()`, `processRefunds()`, `claimProjectFunds()`, and `emergencyWithdraw()` — recurring concern that record-level progress, refund liveness, and payout conditions are misaligned
- Owner wiring around `setNFTContract()` / external NFT checks — noted as a secondary trust-boundary area, but less substantiated than refund-settlement issues

## Issue Directions Seen
- Persistent mismatch between bidder-record accounting and NFT-sold/progress checks, creating settlement-gating inconsistencies
- Refund liveness is a central direction: single-recipient transfer failure can stall batch progress and indirectly block downstream fund release
- Emergency refund paths may ignore whether NFT delivery already occurred, suggesting stale bidder records can trigger double-compensation style outcomes
- Zero-value or dummy bid records are a repeated edge-case direction because they distort progress/accounting without economic substance
- Reentrancy, auction timing, and owner-controlled external contract manipulation were explored, but the durable signal remains much stronger around settlement/accounting logic than classic control-flow exploits

## Useful Context
- Cross-round attention is almost entirely on one contract; the main risk surface is the interaction between bid recording, refund processing order, and project-fund unlock conditions
- The most durable pattern is not isolated arithmetic error but state-machine inconsistency: multiple functions appear to reason about different notions of “processed,” “sold,” or “settled”
- Underexplored but recurring secondary touchpoints include `_bid()` as the source of malformed records and `setNFTContract()` as an external dependency/trust assumption boundary
