# Global Audit Memory

## Scope Touched
- `contracts/RubicProxy.sol` — central custody/routing surface; repeated attention on swap/bridge entrypoints, refund behavior, and shared router-spender trust assumptions
- `rubic-bridge-base/contracts/BridgeBase.sol` — core amount/accounting path tied to fee-on-transfer handling and route funding assumptions
- `rubic-bridge-base/contracts/libraries/SmartApprove.sol` — persistent approval lifecycle and max-approval patterns materially affect downstream drain risk
- `rubic-bridge-base/contracts/architecture/OnlySourceFunctionality.sol` — source-side gating/flow composition relevant to how proxy checks are actually applied
- `rubic-bridge-base/contracts/errors/Errors.sol` — referenced during tracing, but not a primary risk surface
- `src/FlawVerifier.sol` — used for interface/parameter tracing; comparatively underexplored versus proxy/bridge-base logic

## Issue Directions Seen
- Shared allowlist model: routers/gateways treated as trusted execution targets while also retaining spender power over proxy-held assets
- Sticky token approvals: non-revoked or max approvals combine with residual balances to create standing drain exposure
- Balance-delta/accounting gaps: fee-on-transfer or deflationary assets can cause routes to consume less than assumed and subsidize execution from existing proxy balances
- Native asset residue: unspent ETH/refunds can remain stranded in the proxy and later depend on privileged recovery paths
- Config-to-enforcement mismatch: per-token min/max controls appear administratively configurable but not enforced on route entry

## Useful Context
- Audit attention is concentrated on the proxy plus bridge-base dependencies; most durable risk comes from composition across these contracts rather than isolated bugs
- Residual asset accumulation is a recurring theme across both ERC20 approvals and native refund handling
- The sharper retained approval issue is the combined path of shared allowlisting plus persistent approvals, not either mechanism in isolation
- Underexplored areas remain around auxiliary verifier/tracing code and any paths not sharing the same depth of review as `RubicProxy.sol` and `BridgeBase.sol`
