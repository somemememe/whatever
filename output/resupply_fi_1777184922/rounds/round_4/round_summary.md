# Round 4 Summary

## Agent: codex
- files touched: `src/protocol/pair/ResupplyPairCore.sol`, `src/protocol/ResupplyPair.sol`, `src/protocol/pair/ResupplyPairConstants.sol`, `src/protocol/RewardDistributorMultiEpoch.sol`, `src/protocol/WriteOffToken.sol`, `src/libraries/VaultAccount.sol`, plus `src/dependencies/*.sol` and `src/interfaces/*.sol`
- files revisited / highest-attention files: `src/protocol/pair/ResupplyPairCore.sol` was the main focus; `src/protocol/ResupplyPair.sol` was the main secondary file
- main issue directions investigated: borrow/collateral/liquidation/reward state transitions; redemption accounting and `redemptionWriteOff` handling; full-redemption share reset behavior tied to `minimumLeftoverDebt`; handler-mediated redemption/liquidation settlement assumptions
- promising but not retained directions: the external-handler settlement ordering concern around `redeemCollateral` / `liquidate` was surfaced as a candidate issue but was not retained after merge; reward/token flow review in `RewardDistributorMultiEpoch.sol` and `WriteOffToken.sol` did not produce retained findings

## Cross-Agent Status
- main overlap in file/area attention: this round concentrated heavily on pair-core accounting, especially redemption, solvency, borrow-share, and debt-reset logic in `src/protocol/pair/ResupplyPairCore.sol`
- notable differences in attention: no cross-agent differences are present in the logs for this round; only `codex` contributed
- underexplored but suspicious files/functions if clearly supported by the logs: handler integration points in `redeemCollateral` and `liquidate` remained a live area of scrutiny in the round, but did not survive as retained findings; reward-distribution paths were reviewed but remain without retained conclusions this round

## Retained Findings
- retained a high-severity redemption-accounting issue where excess borrower write-offs are discarded, leaving borrower collateral accounting overstated relative to real post-redemption collateral
- retained a low-severity debt-share reset issue where `minimumLeftoverDebt = 0` can leave stale global borrow shares alive after full redemption, contaminating the next borrow cycle
