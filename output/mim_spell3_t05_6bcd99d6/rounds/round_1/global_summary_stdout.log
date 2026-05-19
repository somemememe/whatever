# Global Audit Memory

## Scope Touched
- `cauldrons/CauldronV4.sol` — primary audit focus; core lending flow attention centered on `init`, `updateExchangeRate`, `cook`, and `liquidate`
- `cauldrons/PrivilegedCauldronV4.sol` — privileged extension reviewed mainly around `addBorrowPosition()` and debt assignment behavior
- `cauldrons/PrivilegedCheckpointCauldronV4.sol` — in scope but comparatively underexplored so far
- `FlawVerifier.sol` — in scope but comparatively underexplored so far
- supporting interfaces — used mostly as context rather than primary review targets

## Issue Directions Seen
- `cook()` action-dispatch / state-machine inconsistencies, especially around deferred solvency-check tracking and unsupported or partially handled actions
- oracle / exchange-rate failure handling that falls back to cached or seeded rates inside solvency-sensitive paths
- privileged debt-manipulation surfaces where roles can change another user’s liability without corresponding asset delivery
- liquidation safety tightly coupled to exchange-rate freshness and borrow accounting correctness

## Useful Context
- Audit attention is currently concentrated in cauldron core lending logic rather than peripheral contracts
- Durable patterns so far are logic-level trust and state-accounting issues, not low-level math or interface bugs
- Privileged-role behavior matters materially to insolvency and liquidation outcomes, so extensions around core cauldron debt flows remain high-signal
- Some in-scope files remain lightly traced, so current memory is strongest around V4 cauldron borrow / withdraw / liquidation mechanics
