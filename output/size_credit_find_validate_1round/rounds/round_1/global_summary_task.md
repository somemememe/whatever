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
No global memory yet.

## Latest Round Summary
# Round 1 Summary

## Agent: codex
- files touched: `lib/size-solidity/src/market/libraries/actions/SellCreditMarket.sol`, `lib/size-solidity/src/market/libraries/actions/BuyCreditMarket.sol`, `lib/size-solidity/src/market/libraries/actions/LiquidateWithReplacement.sol`, `lib/size-solidity/src/market/libraries/actions/Deposit.sol`, `lib/size-solidity/src/market/libraries/RiskLibrary.sol`, `src/liquidator/DexSwap.sol`, `src/zaps/LeverageUp.sol`, `lib/size-solidity/src/oracle/v1.5.1/PriceFeed.sol`, `lib/size-solidity/src/oracle/adapters/ChainlinkPriceFeed.sol`, `lib/size-solidity/src/oracle/adapters/UniswapV3PriceFeed.sol`, and attention checks on `lib/size-solidity/src/market/libraries/CapsLibrary.sol` and `lib/size-solidity/src/market/SizeStorage.sol`
- files revisited / highest-attention files: borrower-flow files around `SellCreditMarket.sol`, `BuyCreditMarket.sol`, `LiquidateWithReplacement.sol`, and `RiskLibrary.sol`; secondary attention on `Deposit.sol`, `DexSwap.sol`/`LeverageUp.sol`, and oracle pricing files
- main issue directions investigated: missing borrower collateral/opening-limit enforcement on debt origination and replacement; ETH deposit accounting using contract balance; arbitrary router approval/call surface in zap swap flow; fallback pricing behavior when Chainlink reverts
- promising but not retained directions: liquidity/cap handling surfaced via `CapsLibrary.sol`; code comments around `LeverageUp.sol` quick-fix logic and `Deposit.sol` native-ETH trust assumptions were inspected, but only the deposit-balance issue was retained

## Cross-Agent Status
- main overlap in file/area attention: only one agent reported this round, with strongest concentration in market action libraries, risk checks, zap swap execution, and oracle pricing
- notable differences in attention: no cross-agent divergence visible in this round
- underexplored but suspicious files/functions if clearly supported by the logs: `CapsLibrary.validateVariablePoolHasEnoughLiquidity` and the `LeverageUp.sol` area marked as a “quick fix” were examined but not retained as findings in the visible record

## Retained Findings
- retained issues covered four areas: debt can be opened or reassigned without enforcing borrower opening collateral requirements; WETH/native-ETH deposits can credit pre-existing contract ETH to the next depositor; attacker-chosen routers in zap swaps can drain residual token balances; oracle pricing falls back directly to Uniswap V3 TWAP when Chainlink pricing reverts
- merged severity profile: one critical market-risk issue and three medium/high integration or accounting issues
- retained findings all originated from `codex` in this round


Output only markdown.
