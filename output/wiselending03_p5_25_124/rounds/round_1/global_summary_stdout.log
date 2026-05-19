# Global Audit Memory

## Scope Touched
- `WiseLending.sol`: central attention area for deposit, payback, borrow, and liquidation flows; repeated concern around transfer accounting, WETH mint/deposit behavior, and liquidation invariants
- `WiseCore.sol`: core state/accounting and liquidation bookkeeping repeatedly reviewed alongside lending entrypoints
- `MainHelper.sol`: recurring focus for shared accounting/math and NFT-position token-list handling
- `WiseLowLevelHelper.sol`: relevant to lower-level accounting/plumbing around core lending flows
- `PoolManager.sol`: peripheral attention on borrow gating and market permission checks; `allowBorrow` surfaced as a weak but notable direction
- `WiseLendingDeclaration.sol`: supporting storage/layout context for lending and liquidation state
- `InterfaceHub/IWiseSecurity.sol`: reviewed as a dependency for security checks and gating, but without a durable confirmed direction yet
- `TransferHub/TransferHelper.sol` and `TransferHub/CallOptionalReturn.sol`: important for token transfer semantics, especially nominal-vs-actual transfer accounting and nonstandard ERC20 behavior

## Issue Directions Seen
- Core lending-flow accounting mismatches remain the strongest theme, especially where protocol bookkeeping can trust nominal token amounts or stale state over actual economic movement
- Liquidation paths are a repeated source of risk: repayment assumptions, bookkeeping attribution, and alternate/isolation-pool liquidation routes may diverge from main invariants
- NFT-position state management is a durable concern, particularly token-list cleanup, residual share attribution, and dust-induced metadata corruption or lockup behavior
- WETH/ETH-specific deposit mint flows deserve continued scrutiny because synchronization/pricing assumptions can differ from standard ERC20 paths
- Broad themes like reentrancy, oracle manipulation/staleness, approvals, allowance races, and LASA/timestamp ideas were explored, but the durable signal so far is weaker than the concrete accounting/liquidation defects

## Useful Context
- Cross-round attention concentrated on `WiseLending.sol`, `WiseCore.sol`, and `MainHelper.sol`; these appear to be the highest-value files for continued audit effort
- The most credible issues so far came from concrete state-transition and accounting analysis rather than broad architectural suspicion
- Isolation-pool or verified-liquidation paths are noteworthy because they may bypass assumptions enforced in normal repayment/liquidation flows
- Security and borrow-gating dependencies were inspected, but no stable cross-round conclusion has formed yet beyond keeping them as secondary watch areas
