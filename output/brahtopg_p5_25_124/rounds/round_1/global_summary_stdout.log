# Global Audit Memory

## Scope Touched
- `onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol` — central audit surface; repeated attention on zap-in/zap-out token flow, approvals, ETH handling, and withdrawal accounting
- `onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/interfaces/IBatcher.sol` — relevant for `completeWithdrawalWithZap` behavior and actual-withdrawn-amount assumptions
- `onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/interfaces/IVault.sol` — supporting context for withdrawal flow and amount semantics
- OpenZeppelin token helpers (`IERC20.sol`, `SafeERC20.sol`, `Address.sol`, `ReentrancyGuard.sol`) — used mainly to validate ERC20 return-value, approval, and call-behavior assumptions around `Zapper.sol`

## Issue Directions Seen
- Approval lifecycle is a primary risk area: caller-influenced approvals, allowance target vs call target trust boundaries, and persistent residual allowances
- ERC20 compatibility remains a recurring concern: unchecked `transfer`/`approve` return values and non-zero-to-non-zero approval behavior for zero-first tokens
- Residual-fund handling is a repeated theme: excess native ETH can remain trapped/retained in zap flows
- `zapOut` accounting is a durable concern: logic appears sensitive to nominal/requested withdrawal amounts instead of actual tokens delivered
- Batch withdrawal completion path is comparatively underexplored despite being closely tied to retained amount-mismatch concerns

## Useful Context
- Cross-round attention is heavily concentrated in `Zapper.sol`; interfaces and OZ contracts mostly serve as behavior validation rather than independent bug surfaces
- Both agent passes converged on token movement, approval hygiene, and withdrawal/slippage edge cases as the meaningful audit center
- Governance/sweep hygiene and reporting-style concerns appeared but were not durable relative to the stronger fund-flow and approval issues
- Most retained findings connect to trust assumptions at integration boundaries rather than isolated arithmetic or access-control logic
