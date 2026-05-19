# Global Audit Memory

## Scope Touched
- `hex-otc.sol` — primary audit surface; focus stays on order lifecycle, escrow/state bookkeeping, settlement, and cancellation
- Order creation flow: `offerETH()`, `offerHEX()`, `make()`, `newOffer()` — recurring concern that surfaced order IDs can diverge from the actually persisted live order
- Settlement/refund flow: `buyHEX()`, `buyETH()`, `cancel()` — ETH delivery/refund depends on `transfer`, making recipient compatibility part of order liveness
- `FlawVerifier.sol` — large secondary surface with helper/swap behavior reviewed only lightly; remains suspicious relative to coverage
- `Contract.sol` — structurally unusual in prior logs but still not meaningfully analyzed
- Supporting libs: `erc20.sol`, `math.sol` — reviewed as dependencies, not primary issue centers

## Issue Directions Seen
- Order identifier/accounting mismatches in the OTC flow are the clearest recurring direction, especially where returned IDs, emitted IDs, and stored order slots may not align
- Order lifecycle correctness in `hex-otc.sol` remains central: creation, fill, and cancel paths are tightly coupled through shared state and escrow assumptions
- ETH `transfer` usage in settlement/cancel paths is now a retained direction, since recipient-side gas/payability limits can brick fills or cancellations for some contract participants
- `FlawVerifier.sol` continues to present underexplored helper/swap risk surface, though swap-slippage concerns were only exploratory and not retained

## Useful Context
- Audit attention is still heavily concentrated in `hex-otc.sol`; the strongest confirmed signal is state/identifier propagation rather than token math
- A concrete retained pattern is that externally surfaced order metadata can disagree with the actual active order state
- Another retained pattern is liveness dependence on recipient ETH acceptance behavior, not just internal accounting correctness
- Coverage remains single-agent and uneven: `FlawVerifier.sol` and `Contract.sol` look more suspicious from size/structure than from completed analysis depth
