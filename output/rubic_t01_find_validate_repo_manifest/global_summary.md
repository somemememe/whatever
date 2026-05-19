# Global Audit Memory

## Scope Touched
- `contracts/RubicProxy.sol` — central focus around `routerCall`, router allowlisting, and approval lifecycle
- `rubic-bridge-base/contracts/BridgeBase.sol` — bridge entrypoints, token limit configuration, and admin-controlled state surfaced repeatedly
- `rubic-bridge-base/contracts/libraries/SmartApprove.sol` — approval semantics matter to downstream spender exposure
- `rubic-bridge-base/contracts/architecture/OnlySourceFunctionality.sol` — touched as supporting control-plane context, but still underexplored
- `rubic-bridge-base/contracts/errors/Errors.sol` and `rubic-bridge-base/contracts/libraries/FullMath.sol` — mapped as helper context with limited depth so far

## Issue Directions Seen
- Persistent ERC20 approvals to external gateways/routers are a primary recurring direction, especially where approvals can survive a single route execution
- Allowlist design around approved spenders vs actually executed routers looks structurally risky, with room for spender/router mismatch
- Per-token `minTokenAmount` / `maxTokenAmount` configuration appears present but not enforced at bridge entrypoints, suggesting dead-code-style guardrails
- Admin and route-metadata validation paths were noted as secondary directions, but remain less substantiated than approval and limit-enforcement issues

## Useful Context
- Audit attention is concentrated on proxy-mediated routing and the bridge base layer rather than math/helpers
- The most durable pattern so far is configuration or authorization state existing on-chain without tight coupling to actual execution paths
- Supporting files outside the main proxy/bridge flow have been opened mainly for context and may still hide less-explored edge cases
