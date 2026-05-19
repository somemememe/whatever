# Round 8 Summary

## Agent: codex
- files touched: `src/protocol/pair/ResupplyPairCore.sol`, `src/protocol/ResupplyPair.sol`, `src/protocol/RewardDistributorMultiEpoch.sol`, `src/protocol/WriteOffToken.sol`, `src/libraries/VaultAccount.sol`, `src/dependencies/CoreOwnable.sol`, `src/dependencies/EpochTracker.sol`, `src/interfaces/IFeeDeposit.sol`
- files revisited / highest-attention files: `src/protocol/pair/ResupplyPairCore.sol` and `src/protocol/ResupplyPair.sol` dominated review, especially borrow, interest/exchange-rate update, redemption, and liquidation paths
- main issue directions investigated: pair accounting invariants; borrow/mint-fee debt booking; setter-driven configuration safety for oracle and rate calculator; redemption/liquidation debt-offset mechanics; reward/distributor surface as adjacent context
- promising but not retained directions: a handler-trust issue around `redeemCollateral()` / `liquidate()` and off-pair debt burning was reported by the agent as `F-024`, but it was not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: only `codex` is present in this round; attention centered on `ResupplyPairCore.sol` and `ResupplyPair.sol`
- notable differences in attention: no cross-agent differences are visible from this round’s logs
- underexplored but suspicious files/functions if clearly supported by the logs: `RewardDistributorMultiEpoch.sol` and the redemption/liquidation handler interaction paths were inspected but did not produce retained findings in the merged round state

## Retained Findings
- `F-025`: retained the uncapped `mintFee` issue, where governance/configuration can make new borrows immediately overcharged relative to tokens received
- `F-026`: retained the invalid-address setter issue, where `setOracle()` / `setRateCalculator()` can point to zero or non-contract addresses and brick core pair flows
