# Global Audit Memory

## Scope Touched
- `contracts/DInterest.sol` — central surface across rounds; repeated attention on withdrawal, funding, surplus/deficit, NFT-linked ownership, and dependency/config interactions
- `contracts/DInterestWithDepositFee.sol` — fee-flow accounting and its interaction with core deposit/withdraw paths keeps recurring
- `contracts/rewards/MPHMinter.sol`, `contracts/models/issuance/MPHIssuanceModel01.sol` — reward issuance, vesting/clawback behavior, and admin/control coupling repeatedly matter
- `contracts/NFT.sol` and related NFT factory/mint-control assumptions — deposit control is tightly coupled to NFT ownership and initialization safety
- `contracts/fractionals/ZeroCouponBond.sol`, `contracts/fractionals/FractionalDeposit.sol` — fractionalization/redemption fairness, approval trust, and factory assumptions remain relevant
- `contracts/rewards/Rewards.sol`, `contracts/rewards/Vesting.sol`, `contracts/rewards/MPHToken.sol` — broader rewards-plane admin access, vesting permissions, and ownership transitions were recurring review areas
- `contracts/moneymarkets/yvault/YVaultMarket.sol` and `contracts/zaps/ZapCurve.sol` — peripheral integrations reviewed for accounting correctness and hardcoded/trusted dependency risks

## Issue Directions Seen
- NFT ownership is a core authority boundary; initialization, mint-control, and ownership checks can directly affect deposit withdrawal/funding rights
- Reward mechanics repeatedly intersect with principal flows, especially vesting/clawback behavior and privileged reward-token control
- Funding/deficit accounting is a recurring theme, including stale liabilities, surplus handling, and whether later actors absorb earlier shortfalls
- Fractionalized deposit and bond flows show persistent concern around undercollateralized redemption, approval trust, and first-come-first-served outcomes
- Mutable dependencies and admin-settable components are a repeated control-plane direction across minters, models, token ownership, zaps, and market integrations
- Operational safety gaps such as pause/emergency controls and same-block withdrawal behavior were investigated as recurring risk directions

## Useful Context
- Cross-round attention clusters around the `DInterest` core plus adjacent reward and fractionalization modules rather than isolated single contracts
- The strongest durable pattern is coupling between position ownership representation, reward state, and withdrawal/redemption settlement
- Peripheral integrations (`yVault`, zaps) have not produced retained findings yet, but they remain noteworthy because they sit on accounting and trust boundaries
- Early audit momentum concentrated on exploit validation for concrete asset-flow edge cases rather than purely theoretical governance concerns
