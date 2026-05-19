# Global Audit Memory

## Scope Touched
- `Dexible.sol`, `SwapHandler.sol`: core execution surface; repeated attention on public swap entrypoints, relay boundaries, and broad external route execution authority
- `ConfigBase.sol`, `AdminBase.sol`, `DexibleProxy.sol`: control-plane surface; repeated focus on initialization state, admin assignment, and upgrade/control takeover conditions
- `VaultStorage.sol`, `ICommunityVault.sol`, `IRewardHandler.sol`, `V1Migrateable.sol`: adjacent trust-boundary surfaces around vault/reward/migration hooks, touched as possible extension paths from core execution authority
- `LibFees.sol` plus storage/type/view modules (`DexibleStorage.sol`, `DexibleView.sol`, `SwapTypes.sol`, `TokenTypes.sol`, `ExecutionTypes.sol`): supporting accounting/config context, reviewed but not yet tied to retained issues

## Issue Directions Seen
- Permissionless swap execution combined with unconstrained downstream call routing remains the central asset-loss direction
- Proxy initialization gaps and first-caller admin takeover remain the central control-plane direction
- Trust-boundary questions around privileged vault/reward/migration hooks remain suspicious but less developed than the core swap/proxy paths
- Fee distribution, gas/oracle accounting, reentrancy, affiliate redirection, and zero-address config hazards were explored as secondary directions without retained outcomes so far

## Useful Context
- Cross-round attention is concentrated on execution authority and initialization/admin control rather than pricing or view logic
- The recurring pattern is overbroad authority at two layers: user-facing swap execution and proxy/control initialization
- Several narrower framings of router/relay abuse collapsed into the same broader arbitrary-call theft theme, so they should be treated as variants rather than separate directions
- Supporting modules outside the core swap/proxy path have mostly served as context or edge-case exploration, not standalone confirmed issue centers
