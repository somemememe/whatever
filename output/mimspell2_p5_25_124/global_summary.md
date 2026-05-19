# Global Audit Memory

## Scope Touched
- `src/cauldrons/CauldronV4.sol` - dominant audit surface across rounds; repeated focus on oracle/exchange-rate handling, solvency and liquidation checks, `cook` action composition, strategy release, fee/accounting paths, and interest-rate updates
- `src/cauldrons/interfaces/*` and BoringSolidity support (`lib/BoringSolidity/contracts/*`) - mostly contextual reads to understand token/accounting and external call assumptions; little standalone issue traction so far
- `CauldronV4` functions repeatedly attracting attention: `cook`, oracle update/read paths, `liquidate`, `repayForAll`, `withdrawFees`, `reduceSupply`, and interest accrual / rate-change logic

## Issue Directions Seen
- Oracle state and exchange-rate caching are a primary risk theme, especially bad initialization, stale/failed oracle reads, and downstream effects on solvency or liquidation behavior
- `cook` remains a high-yield direction because combined actions expose bound-check mistakes, permission edge cases, and unexpected strategy-release behavior
- Accounting and debt semantics remain important around interest accrual timing, rate changes, and global repricing effects
- Liquidation, repayment, fee/admin controls, approval/configuration risk, and reentrancy were repeatedly explored but have produced weaker signal than the oracle/accounting directions

## Useful Context
- Cross-agent attention converged heavily on `CauldronV4.sol`; non-Cauldron files were mostly supporting context rather than independent finding sources
- Durable retained issue pattern is that oracle failures or malformed oracle data can corrupt cached pricing and freeze or distort core safety checks
- Another durable pattern is that seemingly administrative or bounded operations in `cook` / rate-management paths can become permissionless or economically incorrect under specific setup/order-of-operations conditions
