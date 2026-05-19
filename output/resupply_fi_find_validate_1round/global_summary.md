# Global Audit Memory

## Scope Touched
- `src/protocol/pair/ResupplyPairCore.sol` — main accounting surface; redemption, write-offs, solvency, interest accrual, and collateral/debt state transitions remain the core review area
- `src/protocol/ResupplyPair.sol` — wrapper/admin and migration surface; oracle refresh plus Convex pool/staking migration paths can perturb core accounting assumptions
- `src/protocol/RewardDistributorMultiEpoch.sol` — reward checkpoint/distribution logic stays relevant because hook execution and token availability can block pair operations
- `src/interfaces/IOracle.sol` — oracle output conventions materially affect exchange-rate, solvency, and redemption math
- `src/interfaces/IConvexStaking.sol`` and related Convex config/integration flows — external staking position accounting and migration can hide or misstate live collateral

## Issue Directions Seen
- Redemption/write-off flows can let internal accounting drift from real collateral state, especially around undercollateralized borrowers, discarded shortfall, and loss-socialization state
- Oracle normalization remains a strong direction: inverted pricing, decimal mismatch, and zero/invalid values can distort solvency and redemption calculations
- Cross-contract coupling between pair core and reward checkpoint/distribution logic is a recurring risk area, including cases where reward-hook execution or missing reward tokens turns accounting actions into availability failures
- Convex migration/integration paths remain promising because staked collateral can become obscured during pool/config transitions while core state still appears coherent
- Interest accrual edge cases near debt-size or arithmetic limits are worth keeping in view because overflowed periods may be skipped rather than reflected in accounting
- Privileged configuration paths (oracle, fee, swapper, Convex pool) remain a standing direction because they reshape external assumptions used by core accounting
- Liquidation-related paths remain adjacent but underexplored relative to redemption/oracle/accounting surfaces

## Useful Context
- Audit attention has consistently centered on accounting integrity and state-faithfulness rather than pure access control
- The durable pattern is internal state staying self-consistent while drifting from actual value/collateral due to write-off handling, oracle assumptions, migration accounting, or skipped accrual
- `ResupplyPairCore.sol` is the hub; wrapper/admin, reward distribution, and Convex integrations mainly matter through how they alter or gate core accounting
- Reward-related concerns are more durable as checkpoint/accounting/availability coupling than as a narrow reward-sniping theme
- External dependency failures matter not only for pricing accuracy but also for liveness when core operations synchronously depend on reward or integration state
