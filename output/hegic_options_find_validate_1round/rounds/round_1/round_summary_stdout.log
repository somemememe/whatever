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
