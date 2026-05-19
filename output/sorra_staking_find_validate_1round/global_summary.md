# Global Audit Memory

## Scope Touched
- `0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol` - dominant audit surface; repeated attention on `deposit()` / `withdraw()`, reward maturation, principal-vs-reward funding, and emergency/owner-controlled exits
- `0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/interfaces/IPoolExtension.sol` - reviewed as the external share-accounting hook surface (`setShare` / extension wiring); suspicious but still less explored than core staking logic
- OpenZeppelin `Ownable` / `ReentrancyGuard` and ERC20 helpers - supporting context for owner authority, transfer semantics, and reentrancy assumptions rather than primary issue sources

## Issue Directions Seen
- Reward-accounting flaws around staking state transitions, especially partial matured withdrawals enabling repeated reward realization
- Pool solvency/principal leakage from paying rewards out of the same token balance that backs user deposits
- Token accounting mismatch when the staking token is not a plain ERC20, especially fee-on-transfer behavior
- Strong owner-control / fund-custody risk centered on emergency withdrawal style paths that can remove user-backed assets without matching liability changes
- Secondary but persistent direction: extension-hook integration risk around external share updates, including desync/bricking-style behavior, though not yet as strong as the core accounting issues

## Useful Context
- The audit remains heavily concentrated on `sorraStaking.sol`; the durable risk picture is driven by accounting and fund-flow design more than imported library behavior
- The same core pattern keeps recurring: reward logic, withdrawal logic, and live token balances are tightly coupled, so accounting correctness dominates the cross-round risk
- Retained findings cluster around insolvency, principal leakage, and repeatable reward extraction rather than nuanced access-control edge cases
- `IPoolExtension` is mainly relevant as an external bookkeeping dependency; its hook surface has been checked enough to stay on the radar, but it is still secondary to the main staking contract
- Supporting library review mostly served to confirm assumptions about owner powers, ERC20 transfer behavior, and reentrancy posture rather than surfacing standalone issues
