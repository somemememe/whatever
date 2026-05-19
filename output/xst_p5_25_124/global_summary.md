# Global Audit Memory

## Scope Touched
- `XST2.sol` — dominant audit surface; core transfer paths, initialization, epoch rollover, pool creation, reserve migration, lock-box/tranche logic, and admin-controlled setters all concentrate here
- `State.sol` / `Getters2.sol` / `Setters2.sol` — supporting state cluster for initialization status, pool pointers, reserve/stabilizer configuration, factor math inputs, and helper/view assumptions
- `Constants2.sol` — supporting constants reviewed alongside core token/state behavior
- `external/IUniswapV2Router02.sol` / `external/IWETH.sol` — lightly touched around router/WETH integration, mainly in pool-creation and migration flows

## Issue Directions Seen
- Boot-time state is a recurring theme: missing or incomplete initialization leaves ownership and core token state unset, with downstream effects on transfer behavior
- Pool wiring and transfer fallback logic look fragile, especially around `_mainPool` dependence and alternate transfer paths
- Economic logic repeatedly points to manipulable pricing/mint-burn behavior from raw pool-balance snapshots, public sync effects, and weak slippage protection
- Epoch/accounting transitions appear sensitive to stale counters or poisoned baselines
- Admin/configuration surfaces matter: reserve/stabilizer setters, tax-related toggles, and owner-controlled addresses/features expand risk around privilege and misconfiguration
- Migration / pool-creation flows are a persistent hotspot, including taxed reserve migration and execution paths that can strand value or revert
- Secondary but suspicious directions include tranche/lock-box handling, helper/view edge cases such as factor calculation failures, and timestamp-sensitive logic

## Useful Context
- Cross-round attention is highly concentrated on `XST2.sol` plus the `State.sol` / `Getters2.sol` / `Setters2.sol` cluster; most durable concerns stem from interactions across that group rather than isolated helper bugs
- Retained issue pattern so far is split between broken foundational state and brittle market/pool mechanics
- Economic-manipulation review and admin-surface review converged on the same conclusion: core behavior depends heavily on mutable on-chain state that can be stale, unset, or externally influenced
- Lock-box/tranche logic and broader external router interaction remain comparatively less explored than initialization and transfer/pool mechanics
