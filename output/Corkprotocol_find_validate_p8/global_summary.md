# Global Audit Memory

## Scope Touched
- `Corkprotocol.sol` — recurrent focus for exploit framing around market setup, hook/callback reachability, and redemption/accounting assumptions
- `CorkConfig.initializeModuleCore` / `CorkConfig.issueNewDs` — implicated in permissionless market creation and attacker-chosen asset / rate-provider registration
- `ModuleCore.initializeModuleCore` / `ModuleCore.issueNewDs` — recurring hotspot for issuance/bootstrap trust boundaries and rollover pricing behavior
- `CorkHook.beforeSwap` — consistent hook-authentication concern; suspected direct-call abuse via forged pool/sender context
- `ModuleCore.sol` rollover / HIYA pricing path — retained concern around near-expiry pricing influencing new CT initialization

## Issue Directions Seen
- Permissionless market bootstrap may allow attacker-controlled redemption assets and exchange-rate providers to wrap real protocol assets in counterfeit markets
- Hook execution trust boundaries look weak, especially around direct invocation of `beforeSwap` without authentic Uniswap v4 `PoolManager` context
- Rollover / issuance pricing appears sensitive to near-expiry state, with potential discounted CT initialization after manipulated premium spikes
- Recurrent but unretained directions: redemption asset-binding mismatches, reserve skew from token donations, and transient balance exposure during unlock/settle flows

## Useful Context
- Early audit attention concentrated on exploitability through setup and routing surfaces rather than deep token math
- Cross-agent overlap is strongest on counterfeit market creation and forged hook-context abuse, suggesting these are durable core themes
- `Corkprotocol.sol` served mainly as the visible PoC/exploit entrypoint, while durable root-cause suspicion extends into config, module initialization, issuance, and hook plumbing
- The highest-value unexplored area remains the boundary between configuration/issuance permissions and downstream hook or rollover assumptions
