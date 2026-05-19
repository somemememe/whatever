# Global Audit Memory

## Scope Touched
- `0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol` — central hotspot for order filling, lifecycle transitions, redemption/finalization, pause coverage, and collateral accounting
- `0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/libraries/PoolMaths.sol` — settlement/finalization math tightly coupled to pool lifecycle and index behavior
- `0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/interfaces/ISilicaPools.sol` — interface expectations matter for settlement and lifecycle edge cases
- `0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/interfaces/ISilicaIndex.sol` — index semantics are relevant to delayed snapshots and non-monotonic decrease handling

## Issue Directions Seen
- Signed order flow shows replay/staleness risk, especially across lifecycle boundaries and until explicit finalization
- Pool lifecycle timing around `startPool`, `endPool`, and redemption remains a primary source of accounting and state-transition issues
- Settlement depends on delayed or manipulable index snapshots; non-monotonic/decreasing index behavior is a recurring failure direction
- Collateral and payout accounting appears fragile for non-standard ERC20 behavior such as fee-on-transfer or negative rebasing
- Emergency pause enforcement looks partial, with protections concentrated in `fillOrder` rather than consistently across related flows

## Useful Context
- Audit attention is concentrated on `SilicaPools` plus its math/interface dependencies rather than external library code
- Durable issues so far cluster around lifecycle/accounting interactions rather than isolated arithmetic bugs
- Finalization is an important gate: several risks involve actions remaining valid or failing unexpectedly before explicit pool finalization
- Index assumptions appear stronger than the system can safely rely on, especially when settlement logic expects monotonic behavior
