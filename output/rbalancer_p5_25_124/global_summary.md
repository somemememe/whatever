# Global Audit Memory

## Scope Touched
- `contracts/StoneVault.sol`: dominant audit surface; withdrawal accounting, share pricing, round rollover, and insolvency behavior repeatedly matter
- `contracts/strategies/StrategyController.sol`: strategy management and forced-withdraw execution are recurring risk areas; strategy onboarding validation also surfaced
- `contracts/token/Stone.sol`: cross-chain LayerZero packet handling and admin/feed message paths are meaningful protocol risk surfaces
- `contracts/AssetsVault.sol`, `contracts/token/Minter.sol`, `contracts/libraries/VaultMath.sol`: secondary supporting surfaces reviewed around asset movement, minting, and math edge cases, but with less confirmed signal so far
- LayerZero OFT / `lzApp` integration files: relevant where custom packet types or nonstandard cross-chain control flow interact with `Stone.sol`

## Issue Directions Seen
- Vault withdrawal paths are the strongest recurring direction, especially instant-withdraw burn/payout mismatches, pricing/fee edge cases, and sourcing of assets during forced withdrawals
- Share-accounting around lifecycle boundaries is a persistent theme: bootstrap pricing before the first round, round rollover transitions, and post-loss / insolvency states
- External-call safety during rollover and strategy interactions remains a live direction, especially reentrancy through strategy callbacks
- Strategy-controller trust and validation assumptions recur, including malformed strategy registration and protocol-wide effects from weak onboarding checks
- Cross-chain custom messaging is a durable risk area, particularly LayerZero admin/feed packet handling rather than plain transfer flow
- Math and bounds behavior appeared repeatedly as a supporting angle, usually tied to pricing, quotas, or insolvency conditions rather than as a standalone theme

## Useful Context
- Cross-round attention is concentrated on `StoneVault.sol`, `StrategyController.sol`, and `Stone.sol`; these are the core contracts shaping most retained issue directions
- The audit has consistently favored behavioral/accounting failures over pure governance-centralization concerns
- `StoneVault` and `StrategyController` are tightly coupled in the main risk stories: vault share/accounting assumptions often depend on controller-held balances and strategy execution semantics
- Secondary files such as `AssetsVault`, `Minter`, and `VaultMath` are better treated as supporting context unless later evidence shows they independently drive exploitability
