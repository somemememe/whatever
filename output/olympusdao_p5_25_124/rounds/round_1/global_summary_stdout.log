# Global Audit Memory

## Scope Touched
- `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol` — central lifecycle surface; repeated concern around `purchase()`/`redeem()` state consistency and market timing assumptions
- `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/bases/BondBaseTeller.sol` — core settlement/accounting/auth hub; attention on market data usage, fee/callback paths, and token transfer handling
- `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/ERC20BondToken.sol` — bond token mint/burn trust assumptions and teller-token coupling mattered across review
- `onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/lib/TransferHelper.sol` — relevant for unchecked or non-standard ERC20 transfer behavior
- Bond purchase / bond-token deployment / redemption flow — recurring cross-file direction where lifecycle ordering and external token behavior interact

## Issue Directions Seen
- Redemption path trusts caller-supplied token context too much, creating arbitrary asset-withdrawal and payout-mismatch risk
- Redemption burns claim tokens before fully validated payout delivery, making ERC20 false-return / non-standard transfer behavior a durable concern
- Purchase flow has lifecycle gaps between market availability and bond-token deployment, allowing users to buy into undeployed claim-token states
- Purchase settlement depends on market metadata that may change between pricing and final settlement, exposing snapshot-consistency issues
- Teller design repeatedly surfaces assumptions about external token behavior, auctioneer-controlled metadata, and callback/fee/auth wiring

## Useful Context
- Audit attention converged heavily on the teller core after broad review of the full scoped Solidity set
- The strongest durable theme is lifecycle integrity: market configuration, token deployment, minting, burning, and payout are not tightly coupled
- External integrations are a major trust boundary: arbitrary ERC20s, non-standard token return values, and mutable auctioneer data all matter
- Fee, callback, guardian, and auth surfaces were examined as suspicious context, but the more durable retained signal remained concentrated in purchase/redeem flow safety
