# Global Audit Memory

## Scope Touched
- `onchain_auto/0x531110418d8591c92e9cbbfc722db8ffb604fafd/src/V3Utils.sol`: primary audit surface; trust boundaries around `execute()` / `onERC721Received`, `_swap`, and position-manager approval lifecycle dominated attention
- `swapAndMint` / `swapAndIncreaseLiquidity` flows in `V3Utils.sol`: reviewed mainly as public entrypoints feeding the callback and swap paths; validation concerns appeared but were less durable than core trust-boundary issues
- `lib/v3-periphery/.../INonfungiblePositionManager.sol` and nearby `lib/` context: supporting interface/reference material rather than an independent issue source so far

## Issue Directions Seen
- Callback authorization remains the strongest recurring direction: approved NFT operators may be able to trigger execution while the contract temporarily controls a position
- User-controlled `swapData` / `_swap` external-call behavior is a persistent arbitrary-call and token-routing trust-boundary concern
- Approval hygiene around the position manager is a recurring theme, especially leftover ERC20 allowances creating downstream zero-first / stuck-flow risk
- Broader public-entrypoint validation questions were explored repeatedly, but mostly as secondary context around the stronger callback and swap surfaces

## Useful Context
- Cross-round attention is highly concentrated in `V3Utils.sol`; other files have mostly served as context
- Both audit passes converged on the `execute()` / `onERC721Received` path as the highest-signal area
- Swap internals and temporary custody of user positions/assets are the main framing for retained risk, more than generic input-validation or observability concerns
