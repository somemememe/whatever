# Global Audit Memory

## Scope Touched
- `0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol`  
  Central audit surface so far; attention has clustered on `stake()`, `harvest()`, `unstake()`, `pendingReward()`, `startStaking()`, and `rescueReward()`, with issue direction centered on reward economics, payout accounting, and owner-controlled reward removal.
- `@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol`  
  Referenced as dependency context only; no independent hotspot established.

## Issue Directions Seen
- Reward liabilities can exceed funded inventory, especially once bonus mechanics are included, creating a recurring insolvency / lockup direction.
- `stakeWeek` appears to be a primary attack surface because bonus scaling may be insufficiently bounded and can amplify reward extraction beyond intended economics.
- Owner-controlled reward recovery via `rescueReward()` is a persistent concern because it may overlap with tokens economically owed to active stakers.
- Reward accounting around accrual, harvesting, and unstaking is the main recurring vulnerability direction; generic config and precision concerns were explored but were less durable than the core economic issues.
- A suspected direction around claiming long-lock bonus before lock completion was explored but not retained.

## Useful Context
- Cross-round attention is highly concentrated in `JuiceStaking.sol`; no durable secondary hotspot has emerged outside that contract.
- The strongest retained themes are economic rather than low-level implementation bugs: bonus amplification, underfunded rewards, and owner withdrawal of owed rewards.
- Review emphasis has split between exploitable payout mechanics and broader safety/configuration concerns, but the durable signal so far is concentrated in pool-balance and reward-liability accounting.
