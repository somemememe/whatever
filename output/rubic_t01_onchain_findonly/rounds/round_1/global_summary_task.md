You maintain a concise global audit memory for future audit agents.

Update the existing global memory by folding in durable observations from the
latest round summary. The goal is an accumulated cross-round audit view, not a
per-round recap.

This memory is optional context only. Findings are stored separately.

Write the updated memory in this exact structure:

# Global Audit Memory

## Scope Touched
- files/contracts/flows that have mattered across rounds, with short issue-direction notes

## Issue Directions Seen
- recurring or promising vulnerability directions seen across the audit

## Useful Context
- compact cross-round observations 

Rules:
- keep it compact
- preserve useful prior context while integrating new durable observations
- prefer stable cross-round patterns over latest-round details
- fold repeated wording into a single clearer observation
- keep the memory descriptive rather than prescriptive

## Existing Global Memory
No global memory yet.

## Latest Round Summary
# Round 1 Summary

## Agent: codex
- files touched: both `contracts/RubicProxy.sol` deployments; both `rubic-bridge-base/contracts/BridgeBase.sol` files; `rubic-bridge-base/contracts/libraries/SmartApprove.sol`; scoped support files were mapped (`FullMath.sol`, `OnlySourceFunctionality.sol`, `Errors.sol`, selected OpenZeppelin upgradeable libs)
- files revisited / highest-attention files: highest attention was on both `RubicProxy.sol` variants, both `BridgeBase.sol` variants, and old-deployment `SmartApprove.sol`
- main issue directions investigated: fee-on-transfer input accounting in the old proxy; persistent max approvals to gateways; unauthenticated use of integrator-specific fee settings across both deployments; whitelist/approval composition between router and gateway; unused min/max token limit configuration
- promising but not retained directions: independent router/gateway whitelisting as a composability risk; configured min/max token limits not enforced at entrypoints

## Agent: merge-review
- files touched: both `contracts/RubicProxy.sol` deployments
- files revisited / highest-attention files: native `routerCallNative` paths in both proxy variants
- main issue directions investigated: accounting/refund handling for unspent native ETH returned during router calls; whether surplus ETH remains on the proxy instead of returning to the user
- promising but not retained directions: no additional non-retained directions are visible from the provided materials

## Cross-Agent Status
- main overlap in file/area attention: both agents converged on the two `RubicProxy.sol` deployments, especially router entrypoints and value/accounting behavior around external router calls
- notable differences in attention: `codex` also spent substantial attention on `BridgeBase.sol` fee logic and `SmartApprove.sol`; `merge-review` is only visibly represented on native ETH refund/accounting behavior in proxy native routes
- underexplored but suspicious files/functions if clearly supported by the logs: old-deployment `SmartApprove.sol` remained a meaningful hotspot because one retained finding came directly from its allowance behavior, while most other scoped support files were only mapped rather than visibly analyzed in depth

## Retained Findings
- retained issues center on proxy fund-accounting and approval safety: old-proxy fee-on-transfer mis-accounting, persistent gateway max approvals, integrator fee impersonation across both deployments, and native-call ETH refund/accounting gaps
- after merge, the retained set keeps the strongest concrete fund-loss and fee-leakage paths; whitelist-pairing and dead min/max-limit concerns from `codex` were not retained in the merged round output


Output only markdown.
