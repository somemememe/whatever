# Global Audit Memory

## Scope Touched
- `0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol` — dominant focus area; `swap()` contains custom referral-fee logic, invariant enforcement, and external-call/callback surface
- `swap()` downstream reserve consumers (`mint()`, `skim()`, `sync()`) — matter because swap-side accounting desync can propagate into reserve-dependent behavior

## Issue Directions Seen
- Swap invariant arithmetic / scaling mismatch weakening the K check and threatening reserve safety
- Referral-fee ordering and reserve-accounting divergence inside `swap()`, especially when fee transfers are not reflected in stored reserves
- Referral attribution trust issues from caller-controlled recipient/referrer fields, including possible self-referral farming
- External-call and callback risk framing around `NimbusCall` / flash-swap style execution, though not yet retained
- Permissionless reserve-maintenance paths (`skim()`, `sync()`) as amplifiers or reset mechanisms for swap-induced desync

## Useful Context
- Cross-round attention is concentrated almost entirely in `Contract.sol`, especially the custom `swap()` flow rather than broader multi-file interactions
- The most durable pattern is that custom referral mechanics are intertwined with core AMM safety checks, so economic logic and reserve accounting cannot be evaluated separately
- Reserve inconsistencies are important not just within `swap()` but for any later logic that trusts stored reserves over live balances
- Non-swap paths remain comparatively underexplored except where they consume or repair reserve state after `swap()`
