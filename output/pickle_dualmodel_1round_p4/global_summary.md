# Global Audit Memory

## Scope Touched
- `src/controller-v4.sol` — central high-risk surface; jar swap flow tied to attacker-controlled jar/converter behavior and delegatecall-like execution exposure
- `src/proxy-logic/uniswapv2.sol`, `src/proxy-logic/curve.sol` — helper swap/liquidity paths repeatedly matter for zero-min execution and slippage/MEV concerns
- `src/strategies/strategy-base.sol`, `src/strategies/strategy-uni-farm-base.sol` — shared strategy harvest/reinvest logic is a recurring source of public-call MEV scrutiny
- Curve strategies including `src/strategies/curve/strategy-curve-3crv-v2.sol`, `src/strategies/curve/strategy-curve-rencrv-v2.sol`, `src/strategies/curve/strategy-curve-scrv-v4_1.sol` — concrete harvest/liquidity legs inherit zero-min swap/add-liquidity exposure
- `src/pickle-swap.sol`, `src/uni-curve-converter.sol` — public LP migration/conversion routes repeatedly flagged for user-principal MEV from zero min-out legs
- `src/strategies/curve/scrv-voter.sol`, `src/strategies/curve/crv-locker.sol` — voter/locker authority and token-routing permissions remain an important trust boundary
- `src/governance/timelock.sol` — bootstrap/admin handoff logic matters for initialization-time governance weakness
- Secondary-but-underexplored attention: `src/pickle-jar.sol`, `src/staking-rewards.sol`, `src/yield-farming/masterchef.sol`, `src/strategies/compound/strategy-cmpd-dai-v2.sol`

## Issue Directions Seen
- Controller-mediated jar swap flows can become arbitrary asset-exposure surfaces when external jar/converter assumptions are weak
- Zero-min swap, add-liquidity, and conversion steps are a repeated MEV/slippage pattern across harvest and migration paths
- Publicly callable harvest/reinvestment remains a recurring value-leak direction, especially in shared strategy logic and Curve/UNI implementations
- Voter/locker authorization gaps are a durable theme, especially where held tokens can be redirected into attacker-chosen gauges or destinations
- Timelock initialization/bootstrap state is a recurring low-confidence governance direction, distinct from ordinary admin centralization
- Broad privileged execution, jar accounting, and reward-parameter abuse directions were explored but not yet retained

## Useful Context
- Cross-round attention clusters around controller, proxy swap helpers, shared strategy bases, Curve voter/locker components, and timelock rather than isolated vault logic
- The strongest retained issues come from unsafe composition between trusted core contracts and attacker-influenced external endpoints or market execution paths
- Shared base contracts appear to propagate risk into multiple concrete strategies, so durable patterns likely sit in common code rather than single strategy variants
- Governance/admin-power concerns appeared often, but only the timelock bootstrap handoff produced a retained issue so far
- Several adjacent modules received review without retained findings, making them better framed as underexplored context than established issue areas
