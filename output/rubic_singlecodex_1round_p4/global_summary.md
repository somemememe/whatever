# Global Audit Memory

## Scope Touched
- `contracts/RubicProxy.sol`: central audit surface for route execution, fee/config handling, token amount validation, and gateway authorization state
- `rubic-bridge-base/contracts/BridgeBase.sol`: recurring focus for bridge-side amount accounting, source routing, and request construction
- `rubic-bridge-base/contracts/libraries/SmartApprove.sol`: relevant through allowance lifecycle behavior tied to gateway/router deauthorization
- `rubic-bridge-base/contracts/architecture/OnlySourceFunctionality.sol`: touched around source-side routing metadata and event/request trust assumptions
- Source-side bridge request flow (`routerCall*`, `RequestSent`, ERC20 routing): repeated attention on how configured inputs, observed balances, and emitted/requested metadata diverge

## Issue Directions Seen
- Stale token approvals can survive gateway or router deauthorization, leaving privileged spend paths after config changes
- ERC20 routing logic may rely on declared input amounts rather than actual tokens received by the contract
- Integrator fee attribution appears user-selectable, creating impersonation or discounted-fee directions
- Configured per-token min/max amount settings exist in scope but may be dormant or unenforced in execution paths
- Source-side event/request metadata trustworthiness surfaced as a secondary direction around routing calls and emitted parameters

## Useful Context
- Cross-round attention is concentrated on `RubicProxy.sol` and `BridgeBase.sol`; most retained themes originate in the boundary between user-facing routing inputs and downstream bridge execution
- The audit keeps surfacing mismatches between configured state and enforced behavior: authorization vs allowance state, declared vs received token amounts, and configured limits vs runtime checks
- Allowance management is not isolated; `SmartApprove.sol` behavior matters because proxy/bridge configuration changes can leave durable token permissions behind
- Source-routing/event integrity has been explored less deeply than amount handling and fee/config issues, but it remains adjacent to the same request-construction paths
