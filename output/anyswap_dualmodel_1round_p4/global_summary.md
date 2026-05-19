# Global Audit Memory

## Scope Touched
- `0x6b7a87899490ece95443e979ca9485cbe7e71522/Contract.sol` — sole cross-round focus; router core, bridge-in/bridge-out entrypoints, and trade-out paths carry the main accounting/integration risk
- `changeVault`, `anySwapOut*`, `anySwapIn*`, trade-out flows — repeated attention on MPC-sensitive control, bridge accounting, token handling, and emitted swap/bridge semantics

## Issue Directions Seen
- Unchecked or weakly checked external token/vault interactions remain the strongest direction, especially where execution and events may continue after failed or partial accounting actions
- Underlying-token flows are a recurring concern when mint/burn/deposit logic trusts nominal input amounts instead of actual assets received or moved
- Asset admissibility is a persistent theme: bridge/trade paths appear willing to interact with arbitrary token-shaped contracts without a strong on-chain allowlist boundary
- Inbound swap validation and replay-style concerns were investigated repeatedly, though not retained as the strongest current direction
- MPC privilege surfaces, initialization assumptions, and fee-related controls drew attention, but mainly as trust-boundary context rather than confirmed core issues

## Useful Context
- Cross-round review stayed entirely within a single router-style contract; no adjacent files were explored, so most durable context is concentrated in `Contract.sol`
- The audit pattern centers on source-chain accounting integrity more than destination-side execution logic
- Event/log credibility versus actual asset movement is an important recurring lens for this codebase
- Most discarded directions still cluster around operational safety themes: replay handling, batch/input validation, pausing/deadlines, reentrancy/slippage, and MPC-admin behavior
