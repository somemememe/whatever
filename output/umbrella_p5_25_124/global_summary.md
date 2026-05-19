# Global Audit Memory

## Scope Touched
- `onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol` - central audit surface; repeated focus on withdrawal arithmetic, reward payout/scheduling, stake accounting, and auxiliary token-recovery logic
- `.../contracts/interfaces/MintableToken.sol` and `.../contracts/interfaces/OnDemandToken.sol` - important for reasoning about shared mint-cap constraints and reward-token solvency assumptions
- `.../contracts/interfaces/IStakingRewards.sol`, `RewardsDistributionRecipient.sol`, `Owned.sol`, `Pausable.sol` - supporting interface/control context around staking and reward administration
- `src/FlawVerifier.sol` and `onchain_auto/src/FlawVerifier.sol` - used as supporting root-cause context, but not a primary independent source of additional durable issue themes

## Issue Directions Seen
- Unchecked subtraction in `withdraw()` / `_withdraw()` as the main drain direction, with both public and internal withdrawal paths repeatedly scrutinized
- Reward insolvency direction tied to farm-local reward scheduling assuming availability under a token-level shared lifetime mint cap (`everMinted` / on-demand mint model)
- Stake accounting mismatch where credited stake may exceed tokens actually received, especially relevant if the staking token is deflationary or otherwise transfers less than requested
- `rescueToken()` surfaced as a secondary suspicion, but with limited cross-round support so far

## Useful Context
- Cross-round attention is highly concentrated in `StakingRewards.sol`; most durable risk themes come from interactions between its accounting and the reward/staking token behaviors
- The strongest recurring pattern is mismatch risk: internal balances/reward promises appear able to diverge from actual token availability or actual tokens transferred
- Supporting interface reads mainly served to validate assumptions about mint authority, distribution roles, and pause/ownership controls rather than opening separate issue families
- Some candidate framings were merged rather than treated as distinct roots, especially around separate withdrawal entrypoints and alternate reward-failure framings
