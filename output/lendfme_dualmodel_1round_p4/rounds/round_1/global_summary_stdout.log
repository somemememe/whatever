# Global Audit Memory

## Scope Touched
- `onchain_auto/0x0eee3e3828a45f7601d5f54bf49bb01d1a9df5ea/Contract.sol` — dominant audit surface so far; repeated focus on `SafeToken` transfer helpers, `supply`, `withdraw`, `repayBorrow`, `liquidateBorrow`, liquidity/borrow accounting, and market suspension/configuration paths
- Core flows repeatedly examined: token in/out transfer handling, borrow/repay accounting, liquidation execution, collateral credit updates, and suspended-market treatment

## Issue Directions Seen
- Reentrancy and callback risk around external token transfers before internal accounting is fully settled
- Accounting mismatches where protocol state may trust requested amounts rather than actual tokens received
- Liquidation edge cases, especially self-liquidation/state aliasing and collateral-credit inconsistencies
- Suspended-market behavior as a recurring source of abnormal liquidation or solvency outcomes
- Admin/configuration/oracle/interest-model control surfaces were reviewed repeatedly, but governance-centralization concerns have not yet produced retained issues

## Useful Context
- Audit attention is heavily concentrated in a single contract; durable patterns are emerging from repeated passes over the same accounting and liquidation codepaths
- Cross-agent overlap is strongest on liquidation logic, market support/suspension handling, and transfer/accounting interactions
- Technical issue directions have been more productive than broad governance-risk themes so far
- No additional in-scope files have meaningfully entered the audit yet; unresolved risk still appears concentrated in `Contract.sol` state transitions and transfer wrappers
