# Global Audit Memory

## Scope Touched
- `onchain_auto/0xe16db319d9da7ce40b666dd2e365a4b8b3c18217/Contract.sol` — main audit focus; oracle pricing trust, liquidation/solvency effects, rewards distribution hooks, and reservoir/accounting behavior all concentrate here
- `onchain_auto/0x3f2d1bc6d02522dbcdb216b2e75edddafe04b16f/Contract.sol` — secondary scope so far; admin/upgrade-control paths drew some concern but saw less cross-agent scrutiny
- rewards distribution flow — claim, transfer, and post-transfer accounting repeatedly surfaced as a durable risk area
- comptroller/market action flow — external distributor integration appears capable of propagating failures into core actions
- oracle pricing flow — price-setting authority and downstream collateral/liquidation math remain the clearest high-impact direction
- reservoir drip flow — accounting progression versus actual token movement has been a recurring mismatch theme

## Issue Directions Seen
- Unrestricted or weakly controlled oracle price updates with direct solvency and liquidation impact
- Reward-claim reentrancy around distributor interactions and payout paths
- Silent transfer-failure handling that clears or advances accounting despite no asset movement
- External rewards/distributor hooks creating DoS risk for core market operations when they revert
- Accounting/state progression diverging from real token transfers, especially in reservoir drip logic
- Admin/upgrade authority concentration remains a background direction, mainly in the less-reviewed companion contract

## Useful Context
- Cross-agent attention heavily converged on `0xe16...8217`, especially its oracle surface; retained findings also cluster there
- The strongest retained pattern is not isolated bugs but trust-boundary failures around external price inputs and reward/distributor integrations
- Multiple retained issues share the same structural theme: protocol state changes continue even when external token transfers or hooks fail
- `0x3f2d...b16f` remains comparatively underexplored relative to the main contract, so observations there are lower-confidence but still notable
- `FlawVerifier.sol` was only lightly touched and mainly as supporting context rather than a central audit target
