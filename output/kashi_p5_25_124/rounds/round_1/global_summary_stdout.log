# Global Audit Memory

## Scope Touched
- `onchain_auto/0xbb02a884621fb8f5bfd263a67f58b65df5b090f3/Contract.sol` — core attention has stayed on the Cauldron lifecycle around `init()`, oracle/rate refresh, solvency checks, `borrow()`, `cook()`, and `liquidate()`
- `init()` / exchange-rate bootstrap flow — recurring concern that fresh-market state can begin from unsafe default rate assumptions
- oracle + solvency paths (`updateExchangeRate()`, `_isSolvent()`, borrow/collateral/liquidation callers) — repeated focus on stale cached-rate dependence in safety-critical decisions
- `cook()` dispatcher / arbitrary call surface — repeated interest in exchange-rate guard semantics and permissionless call behavior that can move or sweep assets
- `liquidate()` and tail admin/accounting region — reviewed as adjacent risk surfaces, but less validated than the exchange-rate / `cook()` issues

## Issue Directions Seen
- Uninitialized or zero-valued exchange-rate state during market bootstrap creating borrow-side drain conditions
- Solvency enforcement depending on cached oracle data that may remain stale across borrow, collateral withdrawal, and liquidation flows
- `cook()` rate-bound logic behaving opposite to intended caller protection, especially around max-rate checks
- Permissionless arbitrary execution through `cook()` exposing stranded ETH/token sweep behavior from assets sitting on the Cauldron
- Secondary but weaker direction around liquidation mechanics and tail admin/accounting surfaces as adjacent attack area

## Useful Context
- Cross-round attention is concentrated in a single Cauldron contract rather than a multi-file interaction surface
- The strongest durable pattern is exchange-rate/oracle state feeding directly into solvency and borrowing invariants
- `cook()` is both a control-flow hub and an asset-movement surface, making it the main overlap area across agents
- Most broader directions were triaged away; durable retained context clusters around rate initialization, stale-rate use, inverted bounds, and stray-asset sweeping
