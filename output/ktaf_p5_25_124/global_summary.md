# Global Audit Memory

## Scope Touched
- `0xf5140fc35c6f94d02d7466f793feb0216082d7e5/Contract.sol` — core attention on Compound-style mint/redeem/borrow accounting, exchange-rate computation, and ERC20 transfer in/out ordering
- `mintFresh` / mint flow — recurring concern around exchange-rate sensitivity to direct token donations and thin-market share issuance distortion
- `redeemFresh`, `borrowFresh`, `redeemUnderlying` — repeated attention on transfer-out ordering, stale account snapshots, and truncation/rounding edge cases
- initialization / admin-config paths in `Contract.sol` — noted for parameter-validation and privileged-setup risk, but less substantiated than accounting paths
- liquidation / seize / delegation-upgrade areas — visible but still comparatively underexplored

## Issue Directions Seen
- Donation-driven exchange-rate inflation as a durable direction, especially where external balance changes can skew mint/redeem pricing
- Outbound transfer before full state update as a recurring reentrancy/stale-snapshot direction, including cross-market interactions
- Integer truncation / rounding-to-zero in redeem paths, especially `redeemUnderlying`-style burn calculations
- General skepticism around initialization and admin-controlled economic parameters, though this remains secondary to concrete accounting issues
- Legacy Compound-style accounting assumptions as a repeated source of edge-case risk framing

## Useful Context
- Audit attention is heavily concentrated in a single lending-token-style contract rather than spread across multiple files
- Cross-agent overlap was strongest on exchange-rate and mint/redeem accounting, suggesting those are the most durable audit themes so far
- The most concrete retained directions are economic/accounting bugs, not generic ERC20 approval or zero-address setup concerns
- Underexplored areas remain liquidation/seize and delegation/admin upgrade logic despite being structurally adjacent to the main accounting flows
