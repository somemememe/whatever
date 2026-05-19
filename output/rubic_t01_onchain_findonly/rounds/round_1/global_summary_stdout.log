# Global Audit Memory

## Scope Touched
- `contracts/RubicProxy.sol` in both deployments: recurring hotspot for router entrypoints, value/accounting behavior, fee handling, and native ETH refund paths
- `rubic-bridge-base/contracts/BridgeBase.sol` in both deployments: attention on fee-setting logic, especially integrator-specific fee usage and entrypoint-side accounting assumptions
- old-deployment `rubic-bridge-base/contracts/libraries/SmartApprove.sol`: durable hotspot for allowance lifetime / persistent max-approval risk to external gateways
- scoped support around proxy/bridge execution (`OnlySourceFunctionality.sol`, `Errors.sol`, OZ upgradeable libs, `FullMath.sol`): mostly mapped for call-flow and accounting context rather than deep issue concentration

## Issue Directions Seen
- proxy-side token/native accounting remains the strongest cross-round direction, including fee-on-transfer inputs and unspent native ETH returned from router calls
- approval safety to third-party routers/gateways is a recurring concern, especially sticky max allowances that outlive a single operation
- fee-configuration trust boundaries are a durable theme, with integrator-specific fee settings appearing usable without clear caller authentication
- router/bridge entrypoints are the main risk surface where external-call composition, accounting, and fee logic intersect

## Useful Context
- both agents independently converged on `RubicProxy.sol`, making proxy execution paths the clearest cross-round concentration area
- retained issues so far cluster around concrete fund-loss, fee-leakage, or allowance-exposure mechanics rather than purely configurational oddities
- `BridgeBase.sol` and old `SmartApprove.sol` matter mainly through how they shape proxy-linked fee and approval behavior
- some explored ideas around whitelist composition and token min/max limits were noted but have not remained part of the durable audit picture
