# Round 1 Summary

## Agent: codex
- files touched: `contracts/RubicProxy.sol`, `rubic-bridge-base/contracts/BridgeBase.sol`, `rubic-bridge-base/contracts/libraries/SmartApprove.sol`, `rubic-bridge-base/contracts/architecture/OnlySourceFunctionality.sol`, `src/FlawVerifier.sol`
- files revisited / highest-attention files: `contracts/RubicProxy.sol`, `rubic-bridge-base/contracts/BridgeBase.sol`
- main issue directions investigated: stale max approvals for gateways after deauthorization; ERC20 routing using declared input instead of actual received balance; unauthenticated integrator fee selection; event / request metadata trustworthiness on source-side routing
- promising but not retained directions: `RequestSent` / `routerCallNative` event-parameter integrity concerns tied to `OnlySourceFunctionality`

## Agent: merge-review
- files touched: `contracts/RubicProxy.sol`, `rubic-bridge-base/contracts/BridgeBase.sol`
- files revisited / highest-attention files: `contracts/RubicProxy.sol`, `rubic-bridge-base/contracts/BridgeBase.sol`
- main issue directions investigated: unenforced configured per-token `minTokenAmount` / `maxTokenAmount` limits
- promising but not retained directions: none visible from the provided material

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `RubicProxy.sol` and `BridgeBase.sol`, especially route execution, fee/config handling, and token-amount controls
- notable differences in attention: codex extended into `SmartApprove.sol` and `OnlySourceFunctionality.sol` for allowance lifecycle and event integrity; merge-review retained focus on dormant size-limit configuration
- underexplored but suspicious files/functions if clearly supported by the logs: `routerCallNative` / `RequestSent` remained a surfaced but unretained hotspot in the codex log

## Retained Findings
- Retained issues covered four distinct themes: stale gateway allowances surviving router removal, ERC20 routes spending against nominal rather than actually received amounts, user-controlled integrator impersonation for discounted fees, and configured token min/max limits not being enforced.
- The retained set stayed centered on `RubicProxy.sol` and `BridgeBase.sol`, with one allowance-lifecycle dependency through `SmartApprove.sol`.
