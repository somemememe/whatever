# Global Audit Memory

## Scope Touched
- `onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol` — sole in-scope vault contract; repeated attention on vault accounting, share issuance/redemption, liquidity routing, and PPS math
- `deposit()` / `withdraw()` — user-facing accounting paths, especially around low-share minting, redemption math, and protection gaps when vault state is skewed
- `earn()` — public capital-routing path; recurrent concern that permissionless calls can aggressively move on-hand funds out of the withdrawal buffer
- `getPricePerFullShare()` — valuation path with zero-supply edge behavior and early-vault revert risk
- `setController()` / `setMin()` / `harvest()` — admin/controller surfaces noted as worth scrutiny, though less substantiated than core vault accounting issues

## Issue Directions Seen
- Empty-vault or externally inflated balance states can distort share pricing and enable zero-/dust-share minting that disadvantages later depositors
- Public `earn()` behavior is a recurring liquidity-management concern because repeated calls can minimize idle balance needed for smooth withdrawals
- Zero-supply / bootstrap-state math is a repeated edge-case direction, especially in PPS calculation and early vault lifecycle behavior
- Vault safety appears tightly coupled to external balance assumptions and controller interactions, making accounting correctness a central audit theme
- Secondary but less developed direction: admin/controller configuration and token-sweep behavior around `harvest()` and controller-setting flows

## Useful Context
- Audit attention is concentrated on a single vault contract rather than a multi-file system
- Cross-agent overlap was strongest on `earn()` and `getPricePerFullShare()`, suggesting those are stable high-signal areas
- The most durable pattern so far is fragility at initialization and low-liquidity states, where accounting and UX assumptions break down fastest
- Controller/admin paths have been looked at less deeply than core share-accounting logic, so they remain contextual rather than established issue clusters
