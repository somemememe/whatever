# Global Audit Memory

## Scope Touched
- `cauldrons/CauldronV4.sol` — primary hotspot across the audit; focus has centered on `cook()`, cached oracle/exchange-rate handling, `init()`, solvency enforcement, and liquidation-sensitive flows
- `cauldrons/PrivilegedCauldronV4.sol` — reviewed mainly as a variant/hook extension of the base cauldron; custom cook-action surface remains less explored
- `cauldrons/PrivilegedCheckpointCauldronV4.sol` — similar follow-up review around privileged/custom hook behavior; less coverage than the base contract
- `FlawVerifier.sol` — used as exploit/hypothesis scaffolding and spot-check context rather than a main issue source

## Issue Directions Seen
- `cook()` state-machine / action-dispatch behavior can desynchronize deferred solvency checks, especially around unsupported or custom actions
- Oracle freshness and cached `exchangeRate` validity are a recurring core risk area: zero, stale, or failed-refresh states affect solvency, borrowing, collateral removal, and liquidation logic
- Initialization-time oracle seeding is a durable concern, particularly when deployment caches a bad or invalid rate
- Variant cauldrons matter mainly for whether privileged or additional cook hooks can reopen base-cauldron accounting and solvency assumptions

## Useful Context
- Audit attention has been concentrated far more on the base cauldron than on privileged variants
- The strongest cross-cutting pattern is dependence on cached price state without consistently requiring a fresh successful oracle update
- Price-invalid states have appeared impactful in both user actions and liquidation paths, including making debt appear healthier than it is
- Privileged/custom extension points remain the clearest underexplored surface relative to how much risk they may inherit from base `cook()` behavior
