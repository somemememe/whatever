# Global Audit Memory

## Scope Touched
- `onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol` — dominant audit focus; issues cluster around Balancer flash-loan callback handling, vault share/NAV accounting, deposit/withdraw paths, Curve swap execution, and pause/exit behavior under stress
- `onchain_auto/src/FlawVerifier.sol` — secondary attention only; used alongside targeted review of accounting helpers and related exploit validation
- Key flows repeatedly examined: flash-loan callback and rebalancing, share-price calculation, withdrawal payout logic, Curve stETH/ETH swap path, and pause-driven exit handling

## Issue Directions Seen
- Callback/authentication weakness around Balancer flash-loan entrypoints remains a central exploit direction because it connects directly to forced strategy actions
- Share-price and NAV accounting are a recurring theme, especially around idle ETH, debt/collateral views, and withdrawal-side proportionality mismatches
- Withdrawal behavior is a persistent risk surface: both overpayment-style logic issues and outright failure-to-exit under adverse liquidity/depeg conditions were explored
- Curve execution risk repeatedly appears through `min_dy = 0` slippage exposure and dependence on stETH/ETH market liquidity
- Admin/control-plane and arithmetic edge cases were inspected, but durable cross-round weight remains lower than the core accounting, callback, and withdrawal surfaces

## Useful Context
- Cross-agent overlap is strongest on `Contract.sol`, with convergence on withdrawal mechanics and zero-slippage Curve swaps as high-signal areas
- The retained picture is a connected vault risk surface rather than isolated bugs: unauthorized rebalance triggering, accounting distortion, unsafe withdrawal payout behavior, and market-liquidity-dependent exits interact materially
- Depeg or severe Curve illiquidity is notable not only for withdrawals but also for operational actions such as `pause()`, making exitability a recurring system-level concern
- Single-agent attention also touched helper/accounting functions and privileged execution hooks, but those directions were not yet durable enough to displace the main vault-flow risks
