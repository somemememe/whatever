# Global Audit Memory

## Scope Touched
- `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol` — dominant audit surface; custody, liquidation/auction settlement, airdrop routing, repayment callbacks, and admin-controlled asset movement all concentrate here
- `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/interface/IXToken.sol` — relevant for repay/liquidation integration assumptions around `XNFT`
- `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/interface/IP2Controller.sol` — controller coupling matters for liquidation and repay notifications
- `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/interface/IPunks.sol` and `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/interface/IWrappedPunks.sol` — matter for CryptoPunks wrapping/type-conversion edge cases
- `0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/interface/IXAirDrop.sol` — relevant to airdrop routing and admin-configurable external-call surface, though mostly examined through `XNFT`

## Issue Directions Seen
- Asset-type/accounting mismatches at deposit or wrapping boundaries can strand collateral, especially around CryptoPunks-to-wrapped-ERC721 handling
- Auction and liquidation settlement remains a primary risk area, especially beneficiary selection, payout/refund mechanics, and behavior under hostile recipients
- Airdrop distribution during distressed states is a recurring concern; ownership/economic-entitlement can diverge during active liquidation
- Admin-capable escape hatches are a major theme: withdrawal and arbitrary-call style functionality may reach user-escrowed assets, not only protocol income
- External dependency mutation and callback-heavy flows create recurring trust-boundary questions, even when individual reentrancy/configuration hypotheses were not retained
- Repayment-path logic tied to caller identity, especially `tx.origin`, remains a lower-confidence but durable direction

## Useful Context
- Cross-round attention is highly concentrated in `XNFT.sol`; other files mostly serve as interfaces for understanding its assumptions
- The strongest retained patterns are custody breakage and privileged asset movement, more than pure pricing/fairness or gas-style issues
- Several discarded hypotheses still indicate the same broader pattern: `XNFT` mixes escrow, auctions, airdrops, and privileged external calls in one contract, making state/entitlement transitions the key audit lens
- `notifyRepayBorrow()` remains comparatively underexplored relative to its integration importance
