# Global Audit Memory

## Scope Touched
- `cauldrons/CauldronV4.sol` — dominant review target; core batch execution, solvency enforcement, borrowing, collateral removal, liquidation, and oracle/exchange-rate handling remain central risk surfaces
- `cauldrons/PrivilegedCauldronV4.sol` — privileged debt/accounting paths matter, especially owner-driven debt assignment against user positions
- `cauldrons/PrivilegedCheckpointCauldronV4.sol` — traced in scope but still underexplored; no retained issue yet
- `FlawVerifier.sol` — touched during scoping/review but no retained issue yet

## Issue Directions Seen
- Batch/state-machine flaws in `cook`, especially ways deferred solvency checks can be neutralized or bypassed by action sequencing
- Liquidation edge cases where extreme insolvency breaks cleanup paths instead of resolving bad debt
- Oracle and cached `exchangeRate` fragility, including failed reads, stale values, and initialization-time invalid pricing
- Privileged cauldron powers that can mutate user debt/collateral state without normal borrower-side value flow
- Secondary attention on verifier/checkpoint-related integrations, but not yet substantiated

## Useful Context
- Cross-round attention is concentrated much more on cauldron core state transitions than on peripheral helper contracts
- The most durable pattern so far is mismatch between intended safety invariants and how multi-step execution/accounting paths actually preserve them
- Pricing assumptions are a recurring trust boundary: both initialization and later solvency/liquidation logic depend on `exchangeRate` correctness
- Privileged variants expand threat surface from pure accounting bugs into operator-imposed user harm
- `PrivilegedCheckpointCauldronV4.sol` and `FlawVerifier.sol` remain lightly explored relative to `CauldronV4.sol` and may still hide adjacent issues
