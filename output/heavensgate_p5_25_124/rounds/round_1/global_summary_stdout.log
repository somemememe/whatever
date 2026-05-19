# Global Audit Memory

## Scope Touched
- `contracts/Staking.sol`: primary focus across rounds; issues cluster around `stake()`, `unstake()`, and `rebase()` interactions, especially epoch accounting and token transfer assumptions
- `contracts/interface/IDistributor.sol`: relevant mainly through `distributor.distribute()` as part of rebase/reward accounting context
- `contracts/interface/IsHATE.sol`: contextual for staking token behavior and transfer semantics
- `setDistributor()` path in `Staking.sol`: lightly explored configuration surface, but not yet a retained issue direction
- OpenZeppelin `Ownable` / `IERC20`: contextual reads only, mainly to frame access control and ERC20 compliance assumptions

## Issue Directions Seen
- Rebase accounting can misclassify newly staked tokens as distributable rewards when epoch timing is stale or expired
- Multi-epoch lag in `rebase()` is a recurring direction, especially around immediate realization of accounting distortions when the contract falls behind
- Raw ERC20 interaction assumptions are a durable concern: code appears to rely on full-transfer or revert semantics in `stake()` / `unstake()`
- Token integration risk has been examined from several angles: unchecked return values, fee-on-transfer / non-standard behavior, and resulting insolvency or user-loss outcomes
- Distributor-linked reward accounting is adjacent to the core staking/rebase issues, though not yet a standalone retained direction

## Useful Context
- Cross-round attention is heavily concentrated on `Staking.sol`; other files have mostly served as interface or dependency context
- Retained findings so far center on two themes: rebase-time accounting errors and unsafe assumptions about ERC20 transfer behavior
- Reentrancy, timestamp dependence, slippage/front-running, and distributor misconfiguration were explored but have not yet emerged as durable issue directions
- The most productive audit pattern has been tracing how epoch state, reward distribution, and token movements interact across `stake()`, `unstake()`, and `rebase()`
