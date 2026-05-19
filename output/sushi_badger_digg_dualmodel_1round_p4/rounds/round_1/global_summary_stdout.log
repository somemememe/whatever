# Global Audit Memory

## Scope Touched
- `contracts/MasterChef.sol` / `contracts/Migrator.sol` — central audit surface; recurring attention on migrator trust, LP custody, reward accounting, reentrancy, and transfer-accounting mismatch risk
- `contracts/SushiMaker.sol` / `contracts/SushiBar.sol` — fee-conversion path and xSUSHI economics repeatedly mattered, especially share pricing/bootstrap behavior and timing-sensitive fee capture around conversions
- `contracts/SushiToken.sol` — governance/delegation accounting remains relevant; transfer flows can diverge from voting-power state
- `contracts/BoringOwnable.sol` — ownership handoff state is meaningful when composed with protocol contracts, especially around lingering `pendingOwner` authority
- `contracts/SushiRoll.sol` / `contracts/Timelock.sol` — reviewed multiple times as adjacent migration/governance surfaces, but without durable retained issues so far
- `contracts/uniswapv2/*` — mostly supporting context for migration and swap behavior rather than a primary retained-issue source to date

## Issue Directions Seen
- Excess trust in migration hooks or privileged migration paths can turn MasterChef-held LP custody into a theft surface
- Reward-distribution logic around external token transfers is a recurring risk area for reentrancy and insolvency-style accounting drift
- Components interacting through fee conversion and staking (`SushiMaker` → `SushiBar`) create timing- and state-dependent economic edge cases
- Governance/accounting state can desync from token balances, particularly in delegation or ownership-transfer flows
- Initialization and bootstrap states matter: first-user share pricing and stale transitional ownership state both produced durable concerns

## Useful Context
- Cross-round attention is most concentrated on `MasterChef` and its directly connected contracts rather than isolated peripheral modules
- The strongest retained themes are composition bugs across contracts: migrator authority, fee conversion into xSUSHI, governance vote tracking, and ownership handoff state
- `Timelock`, `SushiRoll`, and Uniswap migration/swap code remain adjacent context worth remembering, but they have not yet produced lasting findings
- Prior review distinguished many plausible ideas from durable issues; the persistent signal is protocol-state/accounting correctness rather than generic slippage or swap-math concerns
