# Global Audit Memory

## Scope Touched
- `contracts/reserve/DistributionHelper.sol`: repeated focal point in reserve/distribution execution; governance-role persistence, public guardian restoration, public distribution entrypoints, and contract-recipient reentrancy all clustered here
- `contracts/reserve/ExchangeHelper.sol` and `contracts/reserve/GoodReserveCDai.sol`: core adjacent reserve path; attention centered on swap/fee-restocking behavior, approval/slippage assumptions, and interaction sequencing around distribution
- `contracts/staking/GoodFundManager.sol`: oracle-dependent reward/interest logic remains a meaningful direction, especially unchecked or stale oracle answers affecting liveness or payout math
- `contracts/reserve/GoodMarketMaker.sol` and `contracts/utils/BancorFormula.sol`: exploratory attention on pricing/math and initialization edge cases, but not yet a retained issue source
- proxy/bridge surfaces: scanned at a pattern level early, without durable issue traction so far

## Issue Directions Seen
- Governance/control state can persist incorrectly across role or avatar rotation, leaving stale privileged powers alive
- Publicly callable recovery or maintenance paths in reserve/distribution flows can become privilege-restoration or value-extraction surfaces
- Distribution flows that interact with arbitrary recipient contracts remain a recurring reentrancy direction
- Reserve fee-restocking and swap paths are sensitive to missing slippage/bound checks and caller-triggerable execution
- Oracle validation around staking/fund-manager accounting is a standing direction because bad answers can distort rewards or halt collection
- Market-maker and Bancor-style math were suspicious enough for review, but have not yet produced durable audit signal

## Useful Context
- Cross-round attention is concentrated on the reserve/distribution stack rather than isolated contracts
- The strongest retained themes combine control-plane issues with execution-path issues in the same reserve flow
- Several generic defensive-pattern checks were explored, but durable signal so far comes from concrete state-transition and call-sequence behavior rather than style-level concerns
