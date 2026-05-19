# Global Audit Memory

## Scope Touched
- `cauldrons/CauldronV4.sol` remains the dominant surface: `cook()` / `_call()` dispatch, `init()` / clone setup, `accrue`, borrow / repay / withdraw / remove-collateral flows, liquidation seizure/accounting, fee withdrawal / supply reduction, and owner or master-contract parameter storage
- `cauldrons/PrivilegedCauldronV4.sol` remains the main secondary surface, especially `addBorrowPosition()`, privileged debt assignment, and where privileged paths diverge from core `_borrow()` constraints, pricing assumptions, or debt-start semantics
- `cauldrons/PrivilegedCheckpointCauldronV4.sol` matters mainly for liquidation / collateral hook behavior and checkpoint-token callback coupling, including reliance on external callback outcomes
- Supporting interfaces — `interfaces/IOracle.sol`, `interfaces/IBentoBoxV1.sol`, `interfaces/ICheckpointToken.sol`, `interfaces/ISwapperV2.sol`, `interfaces/IStrategy.sol` — continue to matter as assumption surfaces for oracle liveness / decimals, BentoBox share conversions, and external call semantics, though they remain more lightly explored

## Issue Directions Seen
- `cook()` remains a recurring hotspot because flexible action dispatch, arbitrary external calls, and value forwarding can blur intended safety boundaries
- Clone lifecycle / initialization remains a durable direction: uninitialized clones expose first-caller-wins `init()` risk, so deployment and ownership assumptions stay security-critical
- Liquidation logic remains a top-value direction: accounting consistency, rounding, duplicate-borrower handling, partial-seizure edges, blacklist or hook-related reverts, and external-hook interactions can create underpayment or unliquidatability
- Oracle integration remains a core concern: invalid, stale, reverting, cached, or decimal-mismatched rates can distort or block borrow, withdraw, privileged solvency checks, and liquidation behavior
- Fee and debt accounting mismatches remain promising where accrual, fee counters, supply reduction, casts, or debt state diverge from actual BentoBox share availability or effective borrower terms
- Admin-controlled parameterization remains central: weakly constrained updates to collateralization, interest, liquidation settings, or borrow opening fees can abruptly change solvency and debt economics
- Privileged debt paths continue to stand out where debt can be reassigned or created in ways that separate who receives assets, who bears liabilities, and when interest begins accruing
- Shared-balance / skim mechanics remain dangerous where BentoBox-staged collateral or MIM shares can be relied on by one actor and captured by another

## Useful Context
- Cross-round attention stays concentrated in `CauldronV4`; privileged wrappers and interfaces mostly serve as comparison surfaces for validating core debt, pricing, and accounting invariants
- A repeated pattern is internal state appearing coherent while economic reality diverges: liquidation math can under-collect through iteration or rounding effects, fee counters may not match withdrawable shares, and debt burden or recoverability can differ materially from stored values
- Borrower-list semantics matter in liquidation analysis: logic that is locally correct per iteration can still misaccount when the same borrower is processed multiple times
- Post-action assumptions matter more than isolated local checks, especially around oracle failure handling, delayed accrual, BentoBox rounding, liquidation seizure math, callback side effects, and clone initialization / ownership expectations
- Recent review continued to revisit `init`, `accrue`, `cook`, collateral-removal, and `liquidate` as persistent hotspots, but without producing new retained findings; this reinforces them as high-scrutiny areas rather than newly distinct issues
- Interfaces remain more lightly explored than core cauldron logic, so durable assumptions still largely come from how `CauldronV4` consumes oracle, BentoBox, swapper, strategy, and checkpoint-token behavior
