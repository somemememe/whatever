# Global Audit Memory

## Scope Touched
- `SwaposV2Pair.sol`: dominant hotspot across the audit; attention centered on `swap()` invariant/accounting, `initialize()` mutability, and `_mintFee()` fee-mint math
- `SwaposV2ERC20.sol`: secondary attention area for token / permit edge-case review, but no durable issue direction retained yet
- `interfaces/*` and `libraries/{Math,SafeMath,UQ112x112}.sol`: supporting surface for pair math, interface consistency, and oracle/fixed-point assumptions; mainly reviewed in service of pair analysis
- Pair lifecycle and reserve-accounting flows: initialization, swap settlement, fee minting, and reserve-syncing/skimming were the recurring behavioral areas examined

## Issue Directions Seen
- Pair initialization mutability / re-binding risk from non-one-time `initialize()`
- Swap invariant and fee-scaling arithmetic mismatch in `swap()` reserve checks
- Protocol fee minting / LP dilution math in `_mintFee()` remains a notable investigated direction even though it was not retained
- Broader standard-AMM edge cases were probed repeatedly: `skim()` / `sync()`, callback flow, oracle/division-by-zero boundaries, ERC20 compatibility, and permit timing/interface behavior

## Useful Context
- Cross-round attention is concentrated heavily on `SwaposV2Pair.sol`; other files have mostly mattered as supporting context rather than independent hotspots
- The strongest recurring pattern is pair-state/accounting fragility: initialization state, reserve invariants, and fee-accounting math
- Agent coverage split between deep arithmetic exploitability work on pair math and broader architectural sweeps over standard AMM helper paths
- No durable non-pair hotspot has emerged so far outside supporting review of ERC20, interfaces, and math libraries
