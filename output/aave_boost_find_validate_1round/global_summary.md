# Global Audit Memory

## Scope Touched
- `0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol` — central surface so far; attention concentrated on `proxyDeposit` reward economics and `setPool` integration/approval behavior
- `0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/interfaces/IAavePool.sol` — used to validate pool-call semantics and how bad pool targets affect downstream deposit flow
- OpenZeppelin deps (`Ownable.sol`, `IERC20.sol`, `SafeERC20.sol`, `Address.sol`, `Context.sol`) — only lightly checked; mainly supporting context, no durable issue direction yet

## Issue Directions Seen
- Reward-subsidy extraction around `proxyDeposit`, especially fixed-reward or dust-sized looping that can drain the contract’s AAVE reserve
- Low-reward / depleted-balance fallback behavior that can turn subsidy mechanics into a way to sweep remaining AAVE
- Allowance lifecycle risk during `setPool` migrations, with stale unlimited approvals persisting toward old pool targets
- Pool integration validation gaps, especially accepting invalid pool addresses that can black-hole deposits
- Asset/pool parameter consistency was explored but is not a retained direction yet

## Useful Context
- The audit has been heavily concentrated on one contract: `AaveBoost.sol` is the main trust and failure boundary
- Durable concerns are mostly economic and integration-oriented rather than inherited-library bugs
- `IAavePool` matters mainly as an external dependency shaping failure modes; OpenZeppelin code has not been an issue source so far
- Current retained findings cluster around subsidy depletion, residual-balance extraction, approval persistence, and unsafe pool reconfiguration
