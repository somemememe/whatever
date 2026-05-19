# Global Audit Memory

## Scope Touched
- `contracts/game/Game.sol` - dominant focus across rounds; bidding/refund flow, auction lifecycle/state gating, bid-minimum math, claim routing, and payout/share-accounting paths drove most attention
- non-`Game.sol` in-scope Solidity files - read at least once, but produced little sustained follow-up compared with `Game.sol`
- `Game.sol` share/accounting area (`_ownersShare`, `chunksWritenCount`, `claim()`) - noted as comparatively underexplored despite touching payout distribution logic

## Issue Directions Seen
- Auction flow weaknesses in `Game.sol`, especially around bid placement, refunds, and settlement sequencing
- Missing or inconsistent coupling between auction actions and broader game/auction state
- Bid and payout math errors, including minimum-bid progression and share/distribution accounting
- Claim-path destination/routing failures, including zero-address handling
- ERC20 interaction safety on payment and payout paths, especially unchecked return values
- External-call risk during value-return paths, with reentrancy discussed mainly around refunds / ETH sends
- Owner-controlled configuration and miscellaneous edge cases were explored, but with weaker cross-round support than core auction/claim logic

## Useful Context
- Cross-round attention is highly concentrated in `Game.sol`; it is the main contract surface where multiple independent issue directions overlap
- The strongest recurring pattern is that bidding, refunding, settlement, and claiming are tightly connected and tend to surface state-gating plus accounting mistakes together
- Several retained findings cluster around the same user fund movement paths rather than isolated helper logic
- Non-`Game.sol` files remain comparatively low-signal so far, while parts of `Game.sol` payout/share bookkeeping still look less fully exercised than bidding paths
