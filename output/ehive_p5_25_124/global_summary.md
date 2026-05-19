# Global Audit Memory

## Scope Touched
- `0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol`: single-file scope; repeated attention on `startTrading()`, fee/swap/liquidity paths (`swapBack()`, `_addLiquidity()`), privileged roles (`owner`, `teamOROwner`, `_swapFeeReceiver`), and staking flows (`stake()`, `claim()`, `unstake()`, `userEarned()`)
- Trading bootstrap and fee mechanics: recurring concern around configuration-sensitive failure modes, swap execution assumptions, and liquidity/LP-token custody after launch
- Staking subsystem: recurring concern around reward accounting integrity, cap enforcement, claim/unstake behavior, and view/reporting consistency

## Issue Directions Seen
- Privileged control remains a central direction: liquidity custody/withdrawal power, team-controlled switches, and role persistence after ownership changes
- Staking reward logic is a repeated weakness area: cap enforcement, pending-yield cancellation when staking is disabled, and general reward-rate/accounting correctness
- Fee/swap paths repeatedly look fragile: zero-fee transfer failure mode and predictable zero-slippage swaps with MEV/execution-risk exposure
- Reward observability/reporting is suspect: `userEarned()` address/accounting mismatch surfaced across agents
- Secondary but less-confirmed directions included APR/reward-math edge cases, validator-index handling, and anti-bot/approval/configuration checks

## Useful Context
- Cross-round attention is highly concentrated in one contract; no broader multi-file surface has emerged so far
- The strongest overlap across agents is staking logic plus fee/swap mechanics, which makes those the most durable audit themes to carry forward
- Privilege-related risk is not isolated to `owner`; helper roles and fee-receiver style addresses also matter for effective control
- Several weaker checklist-style concerns were raised but not retained; the durable pattern is misaligned incentives/control in launch-fee-liquidity paths and inconsistent staking reward accounting
