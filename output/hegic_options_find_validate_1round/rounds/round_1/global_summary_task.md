You maintain a concise global audit memory for future audit agents.

Update the existing global memory by folding in durable observations from the
latest round summary. The goal is an accumulated cross-round audit view, not a
per-round recap.

This memory is optional context only. Findings are stored separately.

Write the updated memory in this exact structure:

# Global Audit Memory

## Scope Touched
- files/contracts/flows that have mattered across rounds, with short issue-direction notes

## Issue Directions Seen
- recurring or promising vulnerability directions seen across the audit

## Useful Context
- compact cross-round observations 

Rules:
- keep it compact
- preserve useful prior context while integrating new durable observations
- prefer stable cross-round patterns over latest-round details
- fold repeated wording into a single clearer observation
- keep the memory descriptive rather than prescriptive

## Existing Global Memory
# Global Audit Memory

## Scope Touched
- `contracts/Pool/HegicPool.sol` — dominant recurring surface; tranche closure/withdrawal reuse, exits against locked collateral, partial-collateral utilization, NAV/share redemption timing, and active-premium accounting drive most durable risk
- `contracts/Pool/HegicCall.sol`, `contracts/Pool/HegicPut.sol` — option settlement/collateral consumers that matter mainly through how active positions constrain pool solvency and LP withdrawals
- `contracts/Facade/Facade.sol` — persistent payment-path trust boundary; arbitrary approvals, flexible swap/payment routing, exact-output residue/refund loss, and misuse of Facade-held token or ETH balances
- `contracts/Staking/HegicStaking.sol` — fee-share accounting and lockup-state fragility, including zero-supply periods, stranded early distributions, and transfer-based lockup resets/griefing
- `contracts/Staking/SettlementFeeDistributor.sol` — settlement-fee routing/config surface; invalid share splits and undistributable or stranded balances remain durable concerns
- `contracts/Exerciser.sol` — public helper/authorization surface; third-party timing interference or forced early exercise remains a recurring adjacent issue
- `contracts/Options/SimplePriceCalculator.sol`, `contracts/Options/PriceCalculatorWtihUtilizationRate.sol`, `contracts/Options/AdaptivePriceCalculator.sol` — pricing/utilization/oracle inputs repeatedly intersect with collateral measurement, stale data risk, and unit/decimal sensitivity
- `contracts/BondingCurve/ETHBondingCurve.sol`, `contracts/BondingCurve/Erc20BondingCurve.sol`, `contracts/BondingCurve/Linear.sol` — secondary but recurring execution surface; trade safety and missing slippage protection matter where curve pricing meets user funds
- `contracts/Options/OptionsManager.sol` and related interfaces — mostly system-control context, with weaker direct signal than pool, facade, and fee-accounting paths

## Issue Directions Seen
- Pool accounting repeatedly trends toward mismatch between reported balances, locked collateral, active-option obligations, premiums in flight, and redeemable LP value
- Tranche lifecycle and withdrawal-state handling remain a core safety direction, including repeatable withdrawals and exits that ignore locked-liquidity backing
- Utilization/collateral logic shows a durable insolvency pattern where option capacity can be measured against incomplete or overstated available liquidity
- NAV/redemption timing during active options is a recurring economic risk theme, especially when active premiums or liabilities are omitted from share value
- Premium, settlement-fee, and staking-distribution flows repeatedly show value being stranded, misrouted, or becoming undistributable under initialization or configuration edge cases
- Staking/distributor share logic appears brittle around zero-supply periods, invalid share parameters, and lockup/account-state side effects
- External trust boundaries remain important: stale or insufficiently validated oracle reads, facade-level approval exposure, arbitrary payment-path behavior, refund/residue retention, and helper-mediated asset spending
- Public helper-triggered actions remain suspicious where third parties can force timing-sensitive state changes, especially around exercise behavior
- Bonding-curve interactions add a recurring economic-execution direction around unsafe trade parameters rather than core pool solvency

## Useful Context
- Cross-round convergence remains strongest on `HegicPool`; the audit signal is centered on balance-sheet correctness and withdrawal safety more than core option payoff math
- `contracts/Facade/Facade.sol` is the clearest secondary hotspot, consistently appearing as the main external funds-flow and approval boundary around the pool
- The most durable themes combine hard safety flaws with economic mismeasurement: insolvency, locked-liquidity enforcement, LP redemption fairness, premium inclusion, and fee accounting
- Staking, settlement-fee distribution, `Exerciser`, and bonding-curve contracts form the main secondary cluster where state/accounting edge cases or user-control assumptions can redirect or strand value
- Oracle-consuming calculators remain underexplored but important because they feed assumptions into utilization, pricing, and solvency-sensitive pool accounting


## Latest Round Summary
# Round 1 Summary

## Agent: codex
- files touched: `contracts/Pool/HegicPool.sol`, `contracts/Pool/HegicCall.sol`, `contracts/Pool/HegicPut.sol`, `contracts/Staking/HegicStaking.sol`, `contracts/Staking/SettlementFeeDistributor.sol`, `contracts/Facade/Facade.sol`, `contracts/Exerciser.sol`, `contracts/Options/SimplePriceCalculator.sol`, `contracts/Options/PriceCalculatorWtihUtilizationRate.sol`, `contracts/Options/AdaptivePriceCalculator.sol`, `contracts/BondingCurve/Erc20BondingCurve.sol`, `contracts/BondingCurve/ETHBondingCurve.sol`, `contracts/BondingCurve/Linear.sol`
- files revisited / highest-attention files: `contracts/Pool/HegicPool.sol` was the main hub; repeated attention also appears on `contracts/Pool/HegicCall.sol`, `contracts/Pool/HegicPut.sol`, `contracts/Facade/Facade.sol`, `contracts/Staking/HegicStaking.sol`, and the option pricing calculators
- main issue directions investigated: pool collateral and withdrawal accounting; Facade token/approval/swap flows; staking reward and lockup accounting; oracle/pricing assumptions; bonding-curve trading mechanics; ERC20 transfer-accounting assumptions
- promising but not retained directions: dust/zero-premium call options were surfaced by codex but were not retained after merge; broader candidate review is visible, but only the JSON outputs and retained findings confirm which directions survived

## Agent: merge-review
- files touched: from retained findings, attention centered on `contracts/Pool/HegicPool.sol`, `contracts/Facade/Facade.sol`, `contracts/Staking/HegicStaking.sol`, `contracts/Staking/SettlementFeeDistributor.sol`, `contracts/Exerciser.sol`, `contracts/BondingCurve/ETHBondingCurve.sol`, `contracts/BondingCurve/Erc20BondingCurve.sol`, `contracts/BondingCurve/Linear.sol`, `contracts/Options/PriceCalculatorWtihUtilizationRate.sol`, and `contracts/Options/AdaptivePriceCalculator.sol`
- files revisited / highest-attention files: `contracts/Pool/HegicPool.sol` and `contracts/Facade/Facade.sol` dominate the retained set; staking/distributor and bonding-curve files were also recurring review targets
- main issue directions investigated: repeated-withdrawal and unlocked-liquidity failures in pool tranches; Facade balance-stranding/subsidy/theft paths; public helper abuse in `Exerciser`; staking lockup/distribution edge cases; pricing/utilization math mismatches; bonding-curve execution safety
- promising but not retained directions: not visible from the provided logs beyond what survived into retained findings

## Cross-Agent Status
- main overlap in file/area attention: strongest overlap was around `HegicPool.sol`, `Facade.sol`, staking/distributor flows, option pricing calculators, and bonding-curve accounting
- notable differences in attention: codex logs explicitly show direct tracing of pool pricing/collateral math and ERC20 accounting assumptions; merge-review contributed several retained findings on tranche withdrawal state, ETH helper misuse, public exercise helper behavior, and lockup-reset griefing that are not visible in codex’s final JSON
- underexplored but suspicious files/functions if clearly supported by the logs: current retained coverage suggests persistent risk concentration in helper/peripheral entrypoints and accounting joins, especially `Facade.createOption`, `Facade.provideEthToPool`, `HegicPool.withdraw/_withdraw`, `SettlementFeeDistributor.setShares`, and pricing/utilization calculator paths

## Retained Findings
- retained issues center on insolvency and accounting mismatches in the pool, including partial-collateral utilization, stale NAV for LP shares, repeated/overbroad withdrawals, and exact-transfer assumptions
- the Facade remained a major risk area, with public approval misuse, arbitrary payment-path handling, exact-output leftovers, and ETH helper flows turning trapped balances into theft or subsidy paths
- staking/distributor findings focused on fee loss, bad share configuration bricking distributions, and lockup manipulation
- pricing/oracle findings retained around unchecked Chainlink freshness/round validity and put-pricing/utilization decimal/unit mismatches
- additional retained vectors covered public early exercise via the helper and sandwichable bonding-curve trades


Output only markdown.
