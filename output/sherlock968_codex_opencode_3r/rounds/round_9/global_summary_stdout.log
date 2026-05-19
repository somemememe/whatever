# Global Audit Memory

## Scope Touched
- `FluidEPProgramManager.sol`: persistent core hotspot for program funding lifecycle, treasury/stream transitions, shared subsidy accounting, and residue reconciliation across concurrent programs.
- `FluidLocker.sol`: persistent hotspot for unlock/claim semantics and LP-withdrawal lifecycle cleanup, including stranded-token edge behavior.
- `EPProgramManager.sol`: control-plane/timing/auth boundary with manager-locker coupling; durable nonce high-water-mark poisoning/griefing surface remains central.
- `FluidLockerFactory.sol`: recurring integration/admin-control surface; governor-role misconfiguration can become protocol-bricking.
- `Fontaine.sol` + Superfluid path (`SuperTokenV1Library.sol`, manager coupling): recurring stream-rate/buffer integrity and downstream distribution side effects.
- `StakingRewardController.sol`: recurring but secondary distribution-coupling/timing context.
- `SupVesting.sol` / `SupVestingFactory.sol`: secondary recurring lifecycle/admin-transition lockout-style surface.
- `MacroForwarder.sol` and peripherals: repeatedly low retained exploit signal, but still comparatively light attention in deeper paths.

## Issue Directions Seen
- Cross-contract accounting/liveness divergence from tightly coupled funding and reward state transitions.
- Funding lifecycle residue/orphan-state persistence (including treasury rotation leaving unmanaged active streams).
- Shared-stream subsidy fragility: requested-vs-actual rate drift and buffer underfunding effects.
- Unlock/withdrawal semantic bypass or cleanup gaps, including LP-path weakening of intended gating and stranded-asset states.
- Nonce/signature sequencing risks in permissionless execution, including irreversible nonce-floor/high-water-mark griefing.
- Governance/admin control fragility from role-setting edge cases (e.g., zero-address governor bricking control plane).
- Value leakage/drift from clipping, rounding, and tax/distribution transfer semantics.
- Withdrawal-protection/slippage semantic drift via internal minimum/haircut transforms.
- ETH transfer reliability assumptions (fixed-gas/value transfer to contract recipients).
- Token-compatibility and cached-address trust assumptions as recurring secondary directions.

## Useful Context
- Cross-round signal remains concentrated on the end-to-end `FluidEPProgramManager` -> `FluidLocker` -> Factory/Superfluid/Controller path rather than isolated single-contract bugs.
- Recent durable additions were lifecycle/control-plane failures: unmanaged old-treasury streams, LP-withdrawal stranded state, and factory governor misconfiguration bricking admin actions.
- Vesting/admin-abuse narratives continue to recur but remain mostly secondary unless tied to concrete state-transition lockout behavior.
- Broad rereads increased coverage confidence; retained findings still cluster in economic-state reconciliation and flow-integrity boundaries.
