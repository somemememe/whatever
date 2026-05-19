# Global Audit Memory

## Scope Touched
- `Contract.sol` — primary review target; `RubicProxy1` / `RubicProxy2` `routerCallNative` is the persistent hotspot because it forwards caller-chosen router targets and raw calldata
- `ContractTest` areas inside `Contract.sol` — used to model exploitability around proxy-mediated external calls and allowance theft paths
- `interface.sol` — supporting context for router/proxy call surfaces, but not a main implementation hotspot so far

## Issue Directions Seen
- User-controlled external call construction in `routerCallNative`, especially unrestricted target selection plus arbitrary calldata forwarding
- Proxy acting as an unintended ERC20 spender when third parties have pre-existing token allowances to the Rubic proxy
- Native-call entrypoints as potential arbitrary-call gadgets when input/recipient constraints are weak or caller-shaped
- Caller-supplied metadata fields such as `integrator` have been explored, but remain secondary compared with the raw call-surface risk

## Useful Context
- Attention is heavily concentrated on `routerCallNative` across both proxy variants; this is the main cross-round attack surface so far
- The durable retained pattern is not integrator spoofing but externally directed proxy execution that can be turned into token theft via crafted `transferFrom` calls
- `interface.sol` has mainly served as context, suggesting implementation-heavy review is still centered in the proxy call path rather than auxiliary interfaces
