# Global Audit Memory

## Scope Touched
- `0x35a254223960c18b69c0526c46b013d022e93902/Contract.sol` — single bundled hotspot; review has centered on embedded `UpSwing.sol` token logic plus inherited `ERC20.sol` behavior
- `UpSwing._transfer` / sell-to-`UNIv2` flow — pressure accounting, forced settlement, and emitted-vs-actual transfer amount divergence remain the main issue-bearing path
- `ERC20.transferFrom` integration with custom transfer logic — zero-value path can still mutate victim pressure state despite typical allowance expectations
- `UpSwing.releasePressure` — settlement depends on live pair balance / `totalSupply`, making delayed pressure outcomes sensitive to later state changes
- `Steam.sol` and admin/config setters (`setUNIv2`, pauser/admin wiring, leverage config) — examined repeatedly as secondary control-surface context, but not primary finding drivers so far

## Issue Directions Seen
- Non-economic zero-amount token operations interacting with custom accounting/state machines
- Delayed settlement or release logic priced from mutable spot state rather than snapshotted state
- Divergence between `Transfer` events and actual balance deltas on specialized transfer branches
- Centralized/admin wiring and configuration edge cases as recurring review direction, though lower signal than transfer/accounting paths
- Pair interaction / `sync()` / sell-path mechanics as the main place where accounting and integration assumptions break

## Useful Context
- Audit attention has converged on one bundled source file, so most meaningful behavior comes from interactions between embedded contracts rather than separate modules
- The strongest cross-round pattern is custom token mechanics overriding normal ERC20 expectations in subtle edge cases
- Pressure lifecycle logic links user state changes to later market-dependent settlement, creating both griefing-style and manipulable-outcome surfaces
- Metadata files were checked, but durable audit value has come from code-path semantics rather than deployment metadata
