# Global Audit Memory

## Scope Touched
- `onchain_auto/0x1a7981d87e3b6a95c1516eb820e223fe979896b3/Contract.sol` - single-round focal contract; repeated attention on constructor/pair setup, `_transfer`, `swapTokensForEth`, `sendETHToTeam`, and reflection helpers
- Transfer-to-auto-swap flow - persistent hotspot for fee realization, MEV exposure, and payout liveness risk
- Reflection accounting and include/exclude mechanics - persistent hotspot for supply/accounting drift and LP interaction issues
- LP pair treatment - repeated concern that the pair remains reflection-eligible and can accumulate extractable surplus

## Issue Directions Seen
- Reflection math can over-credit balances around fee/team allocation, creating unbacked token value
- Keeping the liquidity pair reflection-eligible can let LP-held surplus be skimmed
- Auto-sell fee swaps with zero minimum output are a recurring MEV/sandwich direction
- ETH fee forwarding design can create transfer-path liveness failures when payout uses strict gas semantics
- Admin/configuration surfaces were reviewed, but the stronger recurring signal stayed in core tokenomics and swap-flow mechanics rather than generic owner-power issues

## Useful Context
- Audit attention stayed almost entirely within one token contract; no other file emerged as a durable hotspot
- Both agents independently converged on the `_transfer` to `swapTokensForEth` path as the main operational risk area
- Cross-round signal is strongest where reflection bookkeeping, LP accounting, and fee-swap execution interact
- Lower-signal themes like missing events, validation gaps, and generic centralization concerns were explored but did not persist as core audit directions
