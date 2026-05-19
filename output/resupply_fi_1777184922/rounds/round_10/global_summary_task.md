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
# Global Audit Memory

## Scope Touched
- `src/protocol/pair/ResupplyPairCore.sol` / `src/protocol/ResupplyPair.sol` — enduring audit center for borrow/collateral/liquidation/redemption accounting, interest + exchange-rate refresh, debt-share lifecycle, fee paths, external handler settlement, Convex transitions, and parameter enforcement
- Convex collateral management in `src/protocol/ResupplyPair.sol` — persistent risk surface around credited collateral vs actual asset location, plus pool/pid compatibility and migration/state-transition safety
- Oracle and rate-calculator integration around pair refresh/admin paths — protocol-wide dependency for price normalization, inversion/decimals handling, freshness/sanity assumptions, zero-price availability, and invalid dependency addresses
- `src/protocol/RewardDistributorMultiEpoch.sol` with `src/dependencies/EpochTracker.sol` — recurring liveness/accounting boundary around checkpoint/integral/claim behavior, reward invalidation, and epoch-length assumptions that affect fee/reward withdrawals
- `src/protocol/WriteOffToken.sol` plus redemption/writeoff flows — durable dependency where token validity or borrower writeoff state affects loss attribution and remaining-collateral accounting
- `src/interfaces/ICore.sol`, `src/dependencies/CoreOwnable.sol`, `src/libraries/VaultAccount.sol`, `src/interfaces/*`, and initialization/admin setters — supporting governance/configuration surface for max-LTV, fee and minimum-borrow parameters, oracle/rate-calculator wiring, and constructor/runtime invariants

## Issue Directions Seen
- Configuration and initialization enforcement is now a firmly recurring direction: unsafe parameter values, invalid module addresses, bad epoch settings, or mismatched Convex pool identifiers can overcharge, brick, or misconfigure core operation
- Oracle math and refresh behavior remain central: decimal mismatches, inversion logic, weak freshness/sanity assumptions, zero-price availability, and bad dependency addresses can break core flows
- Internal accounting vs real asset state is still the strongest recurring theme, especially where redemptions, writeoffs, migrations, fees, or external integrations let balances diverge from recoverable collateral
- Debt/interest accrual and debt-share lifecycle remain live: boundary behavior near caps, full-redemption/reset cleanup, and borrow-parameter constraints can understate debt growth or trap borrowers in unhealthy states
- Redemption/writeoff accounting remains a cross-round direction: borrower writeoff handling, skipped-loss tracking, debt-offset mechanics, and writeoff-token state can misallocate losses or misstate remaining collateral
- Reward/fee distribution remains a recurring secondary direction: zero-share/integral edge cases, reward invalidation, misbehaving reward tokens, or bad epoch configuration can strand balances or break checkpointing/claims

## Useful Context
- The stable audit picture still radiates from `ResupplyPairCore` plus the wrapper pair contract; external modules mostly amplify mistakes in accounting, pricing, liveness, or configuration validation
- A repeated cross-round pattern is state drift: internal debt, share, collateral, reward, or writeoff state can advance in ways that do not cleanly match attributable debt, withdrawable value, or recoverable assets
- Redemption is a recurring desynchronization point, not just a settlement path; borrower-specific writeoff state, debt-offset logic, reward-side behavior, handler mediation, and global debt/share cleanup can interact unexpectedly
- Governance/admin surfaces deserve the same scrutiny as arithmetic paths because constructor-time settings and live setters have repeatedly appeared able to evade safety assumptions or install bricking states
- Latest durable signal strengthens “safe-parameter bounds” as a protocol theme: minimum borrow thresholds, epoch length, and Convex pool selection all materially shape whether existing positions remain operable
- Low-confidence but retained background context includes handler ordering/trust assumptions, fee routing/deposit assumptions, and bounded-integer debt edge cases for future correlation


## Latest Round Summary
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


Output only markdown.
