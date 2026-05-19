# Global Audit Memory

## Scope Touched
- Core recurring scope remains `VirtualToken.sol`, `LamboFactory.sol`, `LamboVEthRouter.sol`, and `rebalance/LamboRebalanceOnUniwap.sol`, centered on debt accounting/isolation, launch wiring, buy/cashout/redemption paths, and rebalance sizing/execution limits.
- Supporting scope remains `LamboToken.sol`, `Utils/LaunchPadUtils.sol`, plus Uniswap-related `interfaces/**` and `libraries/**` used to validate end-to-end assumptions.
- Highest sustained attention has converged on router launch-buy flow semantics (`createLaunchPadAndInitialBuy`) and rebalance execution plumbing.

## Issue Directions Seen
- Debt authority/accounting drift remains a top direction: factory-authorized debt operations can break borrower/pair isolation and pair balance-vs-reserve consistency.
- Launch-pair debt-floor transfer constraints remain a confirmed durability point (`F-020`): vETH debt locking can make publicly provided LP effectively non-burnable.
- Router boundary/slippage weakening is now further reinforced (`F-021`): launch initial-buy path can execute with no caller slippage floor (`minReturn=0`), and owner-controlled fee changes can force dust outcomes or DoS-like buy failure at extreme fee settings.
- Rebalance-control drift remains durable: permissionless execution and sizing/preview boundary mismatch continue to be a recurring concern.
- Liquidity lifecycle assumptions remain fragile, including Uniswap V2 `feeTo` LP mint behavior affecting LP-burn finality expectations.

## Useful Context
- Cross-round convergence continues to favor invariant/boundary failures (authorization, accounting-state sync, slippage/fee boundaries, execution bounds, transfer constraints) over isolated arithmetic issues.
- Round 10 broadened review depth across all in-scope contracts but did not introduce a clearly new durable hotspot outside established debt, router-boundary, and rebalance surfaces.
- Initialization-race and approval-lifecycle concerns were repeatedly explored but remain unretained/low-confidence relative to the dominant confirmed directions.
