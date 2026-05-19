# Global Audit Memory

## Scope Touched
- `unverified_54cd.sol` — attention centers on the ERC1967 proxy-facing flow rather than broad contract surface
- proxy fallback / delegated call path for selector `0x03b79c24` — repeated focus as the apparent source of unauthorized asset movement
- `weETH` custody and recipient routing — issue direction is release/transfer of proxy-held tokens to attacker-chosen addresses
- Uniswap V3 callback liquidation path — relevant as the observed monetization leg after the token release

## Issue Directions Seen
- Proxy-exposed selector appears to reach a privileged asset-release path without effective authorization.
- `weETH` can likely be transferred from the proxy’s custody directly to an arbitrary recipient.
- The same path may also reflect weak or absent per-user/accounting bounds, though this was secondary to the direct unauthorized transfer concern.
- Underlying delegated implementation logic remains a key blind spot; current visibility is into the call site/exploit path more than the implementation itself.

## Useful Context
- Audit attention so far is highly concentrated in a single file and a single proxy-call exploit route.
- The durable pattern is “reachable selector on proxy -> token release from proxy custody -> downstream liquidation,” not multiple independent bug classes.
- Available source context mainly exposes the PoC-facing path and swap callback behavior; the delegated implementation behind the proxy remains opaque.
