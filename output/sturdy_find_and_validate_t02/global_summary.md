# Global Audit Memory

## Scope Touched
- `Contract.sol` / `FlawVerifier.sol`: repeated focus on the exploit path tying Balancer pool exits, oracle reads, collateral toggling, and post-normalization withdrawal into one transaction
- `interface.sol`: mainly used as a signature map for oracle, lending, collateral-management, and Balancer interactions; implementation-level behavior here remains largely unexplored
- Balancer ↔ oracle ↔ lending flow: cross-protocol callback timing and state-dependent valuation is the central surface touched so far

## Issue Directions Seen
- Transient LP/collateral mispricing during Balancer `exitPool` callback windows, especially around `STURDY_ORACLE.getAssetPrice`
- Single-transaction sequencing where temporary overvaluation changes collateral health checks or permissions before state normalizes
- Collateral-disable then withdraw patterns involving `STECRV`, with temporary price inflation masking resulting undercollateralization and bad debt risk

## Useful Context
- Audit attention has concentrated on callback ordering and oracle-read timing rather than broad code coverage
- The retained cross-round pattern is not a standalone oracle bug, but oracle dependence on manipulable in-flight pool state during reentrant execution
- `interface.sol` has mostly served for call-surface mapping (`getAssetPrice`, collateral-use toggles, borrow/withdraw, Balancer calls), so adjacent implementation assumptions remain underreviewed
