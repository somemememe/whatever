# Round 10 Summary

## Agent: codex
- files touched
  - `src/protocol/pair/ResupplyPairCore.sol`
  - `src/protocol/ResupplyPair.sol`
  - `src/interfaces/IERC4626.sol`
  - quick file-map coverage across `src/protocol`, `src/libraries`, `src/dependencies`, and `src/interfaces`
- files revisited / highest-attention files
  - `src/protocol/pair/ResupplyPairCore.sol` was the clear focus, especially solvency checks, swapper flows, redemption, repayment, and reward-related paths
  - lighter follow-up attention on `src/protocol/ResupplyPair.sol` and `src/interfaces/IERC4626.sol`
- main issue directions investigated
  - stale exchange-rate / solvency enforcement around externally callable swapper-assisted flows
  - redemption-path fee handling and underflow/bricking risk
  - ERC20 transfer-handling consistency for leftover debt-token refunds
  - broader scan of borrow, liquidation, reward, and accounting transitions
- promising but not retained directions
  - caller-supplied redemption fee bound issue in `redeemCollateral()`
  - unchecked boolean return on leftover `debtToken.transfer()` in `repayWithCollateral()`

## Cross-Agent Status
- main overlap in file/area attention
  - only one agent participated; attention centered overwhelmingly on `src/protocol/pair/ResupplyPairCore.sol`
- notable differences in attention
  - no cross-agent differences this round
- underexplored but suspicious files/functions if clearly supported by the logs
  - `redeemCollateral()` and the leftover-refund branch of `repayWithCollateral()` were investigated and surfaced as candidate issues, but were not retained after merge
  - reward/accounting code in `ResupplyPairCore.sol` was scanned but did not produce retained findings this round

## Retained Findings
- Retained `F-032`: `leveragedPosition()` and `repayWithCollateral()` refresh the exchange rate before invoking an external whitelisted swapper, but the final `isSolvent` check still uses that cached pre-swap rate; if the oracle can worsen during the swap path, the transaction can end undercollateralized while still passing the solvency check.
