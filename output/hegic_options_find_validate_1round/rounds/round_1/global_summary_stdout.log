# Global Audit Memory

## Scope Touched
- `contracts/Pool/HegicPool.sol` — dominant recurring surface; tranche withdrawal/closure state, locked-collateral enforcement, partial-collateral utilization, NAV/share redemption timing, and ERC20 exact-transfer assumptions drive the strongest durable risk
- `contracts/Pool/HegicCall.sol`, `contracts/Pool/HegicPut.sol` — option collateral consumers that mainly matter through how active positions, premium flow, and settlement assumptions affect pool solvency and LP exits
- `contracts/Facade/Facade.sol` — persistent external funds-flow trust boundary; arbitrary approvals, flexible swap/payment routing, exact-output leftovers, and ETH helper paths can strand, subsidize, or redirect balances
- `contracts/Staking/HegicStaking.sol` — reward accounting and lock-state fragility, especially zero-supply periods, stranded distributions, and transfer-based lockup reset/griefing behavior
- `contracts/Staking/SettlementFeeDistributor.sol` — settlement-fee split/config surface; invalid share settings and undistributable balances remain durable concerns
- `contracts/Exerciser.sol` — public helper/authorization surface where third-party timing interference or forced early exercise remains a recurring issue direction
- `contracts/Options/SimplePriceCalculator.sol`, `contracts/Options/PriceCalculatorWtihUtilizationRate.sol`, `contracts/Options/AdaptivePriceCalculator.sol` — pricing/utilization/oracle surfaces repeatedly intersect with stale data risk and decimal/unit mismatches that feed solvency-sensitive accounting
- `contracts/BondingCurve/ETHBondingCurve.sol`, `contracts/BondingCurve/Erc20BondingCurve.sol`, `contracts/BondingCurve/Linear.sol` — secondary but recurring execution surface; unsafe trade parameters and sandwichable/slippage-sensitive flows matter where user funds meet curve pricing
- `contracts/Options/OptionsManager.sol` and related interfaces — supporting system-control context, with weaker direct signal than pool, facade, pricing, and fee-accounting paths

## Issue Directions Seen
- Pool accounting repeatedly trends toward mismatch between reported balances, locked collateral, active-option obligations, premiums in flight, and redeemable LP value
- Tranche lifecycle and withdrawal-state handling remain a core safety direction, including repeatable withdrawals and exits that ignore locked-liquidity backing
- Utilization/collateral logic shows a durable insolvency pattern where option capacity is measured against incomplete, overstated, or partially collateralized liquidity
- NAV/redemption timing during active options is a recurring economic risk theme, especially when active premiums or liabilities are omitted from share value
- ERC20 transfer-accounting assumptions remain a meaningful direction where exact-transfer behavior is assumed in solvency- or accounting-critical paths
- Premium, settlement-fee, and staking-distribution flows repeatedly show value being stranded, misrouted, subsidized, or becoming undistributable under edge-case initialization or configuration
- Staking/distributor share logic appears brittle around zero-supply periods, invalid share parameters, and lockup/account-state side effects
- External trust boundaries remain important: stale or insufficiently validated oracle reads, facade-level approval exposure, arbitrary payment-path behavior, refund/residue retention, and helper-mediated asset spending
- Public helper-triggered actions remain suspicious where third parties can force timing-sensitive state changes, especially around exercise and ETH-to-pool helper flows
- Bonding-curve interactions add a recurring economic-execution direction around slippage/sandwich exposure rather than core pool solvency

## Useful Context
- Cross-round convergence remains strongest on `HegicPool`; the audit signal centers on balance-sheet correctness, withdrawal safety, and collateral measurement more than core option payoff math
- `contracts/Facade/Facade.sol` is the clearest secondary hotspot, consistently acting as the main approval, payment-routing, and trapped-balance boundary around the pool
- The most durable themes combine hard safety flaws with economic mismeasurement: insolvency, locked-liquidity enforcement, LP redemption fairness, premium inclusion, stale pricing inputs, and transfer-accounting correctness
- Staking, settlement-fee distribution, `Exerciser`, and bonding-curve contracts form the main secondary cluster where state/accounting edge cases or public-entry assumptions can redirect, strand, or subsidize value
- Helper/peripheral entrypoints and accounting joins repeatedly produce retained risk, especially around `Facade.createOption`, `Facade.provideEthToPool`, `HegicPool.withdraw/_withdraw`, `SettlementFeeDistributor.setShares`, and pricing/utilization calculator paths
- Oracle-consuming calculators remain important because freshness, round-validity, and decimal-normalization assumptions propagate directly into utilization, pricing, and solvency-sensitive pool accounting
