# Global Audit Memory

## Scope Touched
- `cauldrons/CauldronV4.sol` — dominant audit surface so far; risk concentrates in `cook()` control flow, solvency gating, oracle/exchange-rate handling, and collateral/share accounting
- `cauldrons/PrivilegedCauldronV4.sol`, `cauldrons/PrivilegedCheckpointCauldronV4.sol` — opened as adjacent variants with privilege-specific surface, but still underexplored relative to core cauldron logic
- `interfaces/IBentoBoxV1.sol`, `interfaces/IOracle.sol`, `interfaces/ICheckpointToken.sol`, `interfaces/IStrategy.sol`, `interfaces/ISwapperV2.sol` — mainly relevant as external assumptions around share accounting, pricing, and execution plumbing
- `FlawVerifier.sol` — reviewed lightly as exploit/harness context; not a primary source of retained issues yet

## Issue Directions Seen
- `cook()` action dispatch can undermine intended deferred solvency enforcement when some actions are not covered by the pending-check logic
- Oracle/exchange-rate paths are a recurring risk area, especially stale data fallback and initialization-time rate caching
- BentoBox share-based collateral accounting remains a strong direction, particularly around `skim=true` flows and claimability of stray shares
- Privileged/blacklist and variant-specific surfaces were noticed but are still secondary compared with the core `CauldronV4` execution/accounting paths

## Useful Context
- Audit attention is heavily concentrated in `CauldronV4`, with adjacent variants and verifier files only lightly sampled so far
- Retained findings already cluster into four durable themes: `cook()` solvency bypass shape, stale oracle usage, zeroed cached `exchangeRate`, and arbitrary capture of stray collateral shares
- The important cross-round pattern is interaction risk between external pricing assumptions and BentoBox share accounting inside multi-action cauldron execution, rather than isolated single-function bugs
