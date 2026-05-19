# Global Audit Memory

## Scope Touched
- `lib/size-solidity/src/market/libraries/actions/SellCreditMarket.sol` / `BuyCreditMarket.sol` / `LiquidateWithReplacement.sol` — core borrower debt-origination and debt-reassignment paths; recurring concern is missing enforcement of borrower opening-collateral constraints during loan creation/replacement
- `lib/size-solidity/src/market/libraries/RiskLibrary.sol` — central risk-check surface tied to opening-limit/collateral validation coverage
- `lib/size-solidity/src/market/libraries/actions/Deposit.sol` — deposit accounting path, especially native-ETH/WETH handling and reliance on contract balance state
- `src/liquidator/DexSwap.sol` / `src/zaps/LeverageUp.sol` — zap/liquidation swap integration surface; focus on router trust, approvals, arbitrary external call reach, and residual-balance exposure
- `lib/size-solidity/src/oracle/v1.5.1/PriceFeed.sol` / `oracle/adapters/ChainlinkPriceFeed.sol` / `oracle/adapters/UniswapV3PriceFeed.sol` — oracle composition and fallback behavior, especially direct fallback from Chainlink failure into Uniswap-derived pricing
- `lib/size-solidity/src/market/libraries/CapsLibrary.sol` / `lib/size-solidity/src/market/SizeStorage.sol` — reviewed as adjacent liquidity/cap/storage context, but not yet a confirmed recurring issue source

## Issue Directions Seen
- Borrower-side risk constraints may be inconsistently enforced across debt opening, purchase, and replacement flows rather than at a single invariant boundary
- Native-asset deposit logic is a recurring accounting risk when credits are derived from ambient contract balance instead of isolated per-call value
- Swap/zap integrations expose a durable direction around attacker-controlled routers, token approvals, and draining of leftover balances held by helper contracts
- Oracle resilience remains a key direction: fallback behavior after primary feed failure can silently shift trust to weaker pricing sources
- Liquidity/cap validation and quick-fix-marked leverage code surfaced as suspicious adjacent areas, though not yet retained as findings

## Useful Context
- Audit attention concentrated most heavily in market action libraries, risk checks, zap execution helpers, and oracle pricing composition
- The strongest cross-round pattern so far is boundary/invariant slippage: critical borrower eligibility, accounting isolation, and trust assumptions appear enforced locally and unevenly rather than globally
- Helper/integration contracts (`DexSwap`, `LeverageUp`, oracle adapters) look materially important because they bridge external systems and may hold transient balances or pricing authority
- No cross-agent divergence exists yet; current memory is based on a single round with multiple retained issues clustered around origination risk, deposit accounting, swap trust, and oracle fallback design
