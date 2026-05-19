# Global Audit Memory

## Scope Touched
- `contracts/TokenRewards.sol`: recurring center of attention around referral binding/initialization, third-party claim behavior, and reward-swap slippage/liveness
- `contracts/DecentralizedIndex.sol`: transfer-hook fee-swap paths repeatedly mattered, especially residual-supply / dust liveness and broader rescue/flash-sensitive surfaces
- `contracts/WeightedIndex.sol`: `bond()` kept drawing review for state-ordering, mint-before-payment, and reentrancy / undercollateralization angles, though not retained
- `contracts/StakingPoolToken.sol`: relevant mainly through share-update coupling and transfer restriction interactions that can amplify upstream reward/referral issues
- `contracts/interfaces/` (`IDecentralizedIndex`, `ITokenRewards`, `IReferral`): useful for tracing trust boundaries and call surfaces around rewards/referrals

## Issue Directions Seen
- Referral control is a primary cross-round theme, especially first-write / first-claim paths that let outsiders permanently influence user reward relationships
- Permissionless actions on behalf of users are a repeated risk direction when they can lock in state or redirect later value flows
- Fee-swap and reward-swap logic show a recurring liveness/arithmetic pattern: edge-case amounts, failed swaps, or accumulated dust can strand value or freeze flows
- State ordering around mint/bond and external-token interactions remains a standing reentrancy / undercollateralization direction even where not yet retained
- Admin/rescue/configuration and pricing-manipulation angles were explored as secondary surfaces but have not yet produced retained issues

## Useful Context
- Cross-agent overlap was strongest on `TokenRewards.sol`, `DecentralizedIndex.sol`, `WeightedIndex.sol`, and `StakingPoolToken.sol`
- `TokenRewards` was the most consistent hotspot, with referral handling the clearest durable pattern across investigations
- Several retained issues were liveness-oriented rather than direct theft: frozen transfers, stranded fee balances, and broken reward-routing state
- `StakingPoolToken` appears less as an origin of bugs than as an amplifier or constraint layer for reward/referral behavior elsewhere
