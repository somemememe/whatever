# Global Audit Memory

## Scope Touched
- `0x37ea5f691bce8459c66ffceeb9cf34ffa32fdadc/contracts/GradientMarketMakerPool.sol` — dominant hotspot; liquidity/share accounting repeatedly stressed around orderbook transfer/return paths, deposits, withdrawals, and rewards
- `provideLiquidity` / `withdrawLiquidity` — LP mint-burn behavior appears misaligned with true pool assets when capital is moved out of the contract
- `transferETHToOrderbook` / `transferTokenToOrderbook` / `receiveETHFromOrderbook` / `receiveTokenFromOrderbook` — orderbook parking/return flow is the main source of accounting edge cases, including zero-liquidity states
- `claimReward` — reward logic has been tied to deposit-balance vs LP-share inconsistencies
- Interfaces (`IGradientMarketMakerPool`, `IGradientRegistry`, `IUniswapV2Pair`, `IUniswapV2Router`) — revisited mainly for integration assumptions, but substantive risk remains concentrated in pool-side accounting

## Issue Directions Seen
- Recurring core direction: internal liquidity/share accounting diverges from economically controlled assets when funds are temporarily parked in the orderbook
- LP share inflation remains a central pattern, especially for deposits made while orderbook-held assets are excluded from active pool balances
- Reward entitlement accounting appears to track nominal deposits differently from LP ownership, creating mismatch-based extraction or unfairness risk
- Token accounting that credits nominal transfer amounts instead of actual received amounts is a standing concern
- Full orderbook drain to `totalLiquidity == 0` is a durable brick direction: return paths can revert, withdrawals can be blocked, and recapitalization/share minting can fail

## Useful Context
- Cross-round attention is highly concentrated in a single contract rather than spread across the system
- The most durable pattern is not generic admin abuse but state inconsistency created by asset movement between the pool and external orderbook
- Zero-liquidity handling is especially sensitive because multiple downstream behaviors depend on `totalLiquidity` staying nonzero and economically meaningful
- Retained findings consistently cluster around accounting invariants: asset custody, LP supply, and reward basis do not always move in sync
- Earlier admin-emergency and slippage-check concerns were explored but did not persist as the strongest cross-round themes
