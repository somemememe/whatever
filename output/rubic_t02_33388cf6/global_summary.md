# Global Audit Memory

## Scope Touched
- `Contract.sol` — central attention on public `routerCallNative` forwarding behavior and proxy-mediated external call surface
- `FlawVerifier.sol` — repeatedly used to validate `_attemptDrain` assumptions and confirm concrete drain mechanics
- `interface.sol` — reviewed around `routerCallNative`, `integrator`, and helper/library references; useful for call-shape context but no separate root cause retained

## Issue Directions Seen
- Public arbitrary-call exposure through `routerCallNative` when both target `router` and raw calldata are caller-controlled
- Proxy/spender abuse pattern where forwarded calls can invoke ERC20 `transferFrom` using pre-existing user approvals
- Recurrent question of whether declared swap/bridge parameters meaningfully constrain actual token movement; so far points toward weak coupling rather than an independent retained issue
- `integrator`/routing metadata spoofing was explored as a privilege direction, but not retained as a distinct root cause

## Useful Context
- Cross-round durable center of gravity is the gap between user-facing routing parameters and the actual externally executed call
- The retained issue is not generic library misuse; it depends on the contract acting as an already-approved spender during arbitrary forwarded execution
- Helper libraries in `interface.sol` (`TransferHelper`, `SafeTransferLib`, `Clones`, `Nonces`) were scanned and currently serve as context, not independent issue anchors
