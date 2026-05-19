# Global Audit Memory

## Scope Touched
- `contracts/protocol/lendingpool/LendingPool.sol`: central review hub; repeated concern around `PMTransfer` and borrow-path state transitions
- `contracts/protocol/tokenization/AToken.sol`: relevant to collateral transfer / seizure mechanics linked to `PMTransfer`
- `contracts/protocol/libraries/logic/ValidationLogic.sol`: borrow validation depended on oracle outputs, including zero-price handling
- `contracts/protocol/libraries/logic/GenericLogic.sol`: collateral / liquidation accounting paths rely on oracle-fed valuations
- `contracts/misc/AaveOracle.sol`, `contracts/interfaces/IChainlinkAggregator.sol`: price-source trust assumptions, especially zero values and missing freshness checks
- `contracts/adapters/FlashLiquidationAdapter.sol`: reviewed as a secondary hotspot; same-asset liquidation settlement behavior remains worth tracking though not retained

## Issue Directions Seen
- Authorization and accounting around `PMTransfer` are a recurring high-risk theme, especially paths that let collateral move or be seized without normal debt-resolution constraints
- Oracle robustness is a core audit direction: zero-price acceptance and stale Chainlink data can distort borrowability, collateral valuation, and liquidation decisions
- Cross-module interactions between lending, tokenization, and valuation logic matter more than isolated function review in this codebase
- Liquidation adapter edge cases remain a live secondary direction, particularly around settlement assumptions in flash-liquidation flows

## Useful Context
- Early audit attention concentrated heavily in lending-pool and oracle code; those areas currently define the main cross-round risk surface
- Durable retained findings so far cluster into two families: `PMTransfer` collateral-removal flaws and oracle-safety failures
- `FlashLiquidationAdapter.sol` produced a plausible but unretained candidate, making it a standing hotspot rather than a cleared area
- `onchain_auto/` had only repo-level discovery and has not yet contributed substantive contract analysis
