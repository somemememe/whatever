# Global Audit Memory

## Scope Touched
- `Contract.sol`: primary attention on the Balancer `exitPool()` callback path and downstream collateral state transitions; repeated focus on `getAssetPrice`, `setUserUseReserveAsCollateral`, borrow/liquidation state, and post-disable withdrawal flow
- `FlawVerifier.sol`: secondary hotspot around verifier/orchestration paths, including unwind/callback handling and one-shot `executeOnOpportunity()` behavior
- `interface.sol`: only lightly scanned so far; mostly relevant as supporting definitions, still comparatively underexplored
- Flow: Balancer exit callback -> temporary LP valuation distortion -> collateral disable -> later withdrawal / solvency consequences
- Flow: verifier execution/callback authorization and single-use opportunity execution paths

## Issue Directions Seen
- Read-only reentrancy / callback-time oracle distortion during Balancer exit causing temporary collateral overvaluation
- Using the manipulated valuation window to disable collateral that would otherwise be required, with later withdrawal proceeding without a fresh effective solvency check
- Verifier-level availability/griefing around one-shot `executeOnOpportunity()` consumption
- Callback and unwind authorization remains a recurring review direction, but less developed than the oracle-manipulation cluster
- Slippage / MEV / zero-min-out unwind risk has appeared repeatedly as a secondary but unretained direction

## Useful Context
- Cross-round attention has concentrated much more on `Contract.sol` and `FlawVerifier.sol` than on `interface.sol`
- The dominant audit theme is not generic reentrancy, but state changes made during transient pricing distortion and their persistence after the pricing window closes
- Both agents converged on the same Balancer-exit/oracle/collateral sequence; verifier operational risks were explored more unevenly
- `executeOperation()` and related callback-auth paths have had narrower coverage than the main collateral manipulation flow
