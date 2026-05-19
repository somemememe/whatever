# Global Audit Memory

## Scope Touched
- `contracts/RouteProcessor2.sol`: dominant audit surface; untrusted route execution, external pool callbacks, router-held asset accounting, Bento interactions, and native unwrap behavior repeatedly mattered
- `contracts/InputStream.sol`: supporting parser/control-flow context for how route commands are decoded and executed
- `interfaces/IBentoBoxMinimal.sol`: supporting context for Bento share/recipient/accounting paths tied to router inventory and `processUserERC20`
- `interfaces/IPool.sol`, `interfaces/IUniswapV2Pair.sol`, `interfaces/IWETH.sol`: supporting context for pool trust assumptions, swap callbacks, and native wrapping/unwrapping flows

## Issue Directions Seen
- Callback trust in V3/CL-style pool integrations is a central direction: route-selected pools can be insufficiently validated and abuse swap callbacks
- Router execution appears weakly bound to caller intent/funding, creating repeated drain directions against router-held ERC20, ETH, and Bento inventory
- Token/source binding around `processUserERC20` and Bento paths is a recurring theme: declared input assets may diverge from what the route can actually pull
- Native asset handling remains a recurring risk area, especially balance-based unwrap/payout behavior instead of amount-scoped transfers
- Broader slippage, deadline, and generic validation concerns were explored, but the durable pattern is more about trust/accounting boundaries than user-protection checks

## Useful Context
- Cross-round attention concentrated overwhelmingly on `RouteProcessor2.sol`; other scope areas remain comparatively underexplored
- `InputStream.sol` mainly served to confirm that dangerous behavior is reachable through route parsing rather than containing the primary risk itself
- The strongest repeated pattern is public, user-supplied route data steering privileged asset movement without tight provenance checks
- A Bento surplus-capture idea was examined but did not remain durable; Bento relevance persists mainly through router inventory and asset-source confusion
