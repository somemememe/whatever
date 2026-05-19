# Global Audit Memory

## Scope Touched
- `0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol` — central hotspot; reward scheduling, lifetime budget accounting, payout solvency, and stake-balance bookkeeping all concentrate here
- `0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/OnDemandToken.sol` / `0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/MintableToken.sol` — matter for whether advertised rewards are actually backed by mint capacity / cap semantics
- `0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/IStakingRewards.sol` / `RewardsDistributionRecipient.sol` — supporting interface context around reward distribution flow, but not independent issue centers so far
- `0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/IBurnableToken.sol`, `Pausable.sol`, `Owned.sol` — reviewed for surrounding control/context; no durable separate direction yet

## Issue Directions Seen
- Reward emissions may be scheduled beyond actually reservable mint capacity, creating a backing/solvency gap between promised rewards and token supply limits
- Lifetime reward-budget accounting appears vulnerable to overconsumption from zero-stake windows, early termination, or otherwise undistributed emissions still being counted as spent
- Staking-share ledger may drift from real token balances for fee-on-transfer or rebasing stake tokens, leading to withdrawal or reward insolvency
- Narrow reward-supply storage/accounting (`uint96 totalRewardsSupply`) is a recurring arithmetic edge if token cap or aggregate emissions can exceed 96-bit bounds

## Useful Context
- The audit attention is currently concentrated on the `StakingRewards` farm design and its assumptions about token minting behavior rather than on admin-control surfaces
- Durable pattern: multiple retained directions are different expressions of the same core risk class — accounting promises are made using internal counters that may not stay aligned with actual token backing or balances
- Auxiliary ownership / pause / distribution-recipient interfaces were checked mainly as context and have not yet produced a separate cross-round issue theme
