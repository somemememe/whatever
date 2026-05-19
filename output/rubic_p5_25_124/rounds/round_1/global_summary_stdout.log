# Global Audit Memory

## Scope Touched
- `contracts/RubicProxy.sol` — central source-side routing surface; repeated attention on token pull/approval lifecycle, fee selection inputs, and route parameter handling
- `rubic-bridge-base/contracts/BridgeBase.sol` — core routing/accounting path; recurring concerns around nominal-vs-actual token amounts and unenforced token route bounds
- `rubic-bridge-base/contracts/libraries/SmartApprove.sol` — persistent approval behavior is a primary cross-round risk area, especially around max approvals that outlive a route
- `rubic-bridge-base/contracts/architecture/OnlySourceFunctionality.sol` — lightly touched around source-side event/metadata emission, but not yet a confirmed issue center
- `src/FlawVerifier.sol` — used mainly as exploit/framing support for approval-drain scenarios rather than as an independent issue source
- `rubic-bridge-base/contracts/errors/Errors.sol` / `FullMath.sol` — supporting context only, with no durable standalone issue direction yet

## Issue Directions Seen
- Sticky unlimited ERC20 approvals to external gateways/routers, including persistence after route completion or router delisting, creating long-lived drain exposure for proxy-held balances
- ERC20 routing/accounting mismatch where execution trusts configured or nominal input amounts instead of actual tokens received, especially relevant for fee-on-transfer behavior
- Stored per-token routing bounds (`minTokenAmount` / `maxTokenAmount`) appear disconnected from public entrypoint enforcement
- Fee/integrator parameter trust: user-controlled integrator selection may let arbitrary callers inherit discounted fee schedules
- Lower-confidence observability/event-metadata inconsistencies exist on native routing paths, but this direction remains underexplored and unconfirmed

## Useful Context
- Cross-round attention is concentrated on the `RubicProxy` → `BridgeBase` → `SmartApprove` path; approval persistence is the strongest repeated theme
- The most durable issues are source-side asset custody and accounting problems, not destination-side bridge semantics
- Several approval-related observations collapsed into one broader pattern: external-call routes can leave residual token authority that matters after configuration changes
- Native-route metadata/event concerns and admin-style sweep/observability ideas surfaced, but did not yet show the same durability as approval, accounting, bounds, and fee-trust themes
