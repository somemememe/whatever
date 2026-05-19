# Global Audit Memory

## Scope Touched
- `0xde46fcf6ab7559e4355b8ee3d7fba0f2730cddd8/Contract.sol` - single in-scope hotspot across the audit; repeated attention on reward accrual, round accounting, join/reactivation flow, VIP privilege logic, and insurance settlement branches
- `withdraw()` - core payout/accounting path; multiple failure modes around round-balance handling and end-branch payment logic
- `calcStepIncome` - externally reachable reward-crediting path tied to fabricated withdrawable balance risk
- `joinGame()` / `activeParent()` - account reactivation and round-transition path; state carryover between inactive/prior-round users remains a key direction
- `settlementStatic()` / `setAmbFlag()` - surfaced during callable-function scan but remain comparatively underexplored

## Issue Directions Seen
- Public or insufficiently gated reward-accounting functions may let users mint or accelerate withdrawable value
- Round-boundary and final-branch accounting is a recurring weakness, especially where balances are zeroed or reassigned before payout
- User lifecycle transitions (`join`, reactivation, parent activation) appear prone to stale-state reuse across rounds
- Privileged or hardcoded address treatment is a persistent fairness/backdoor direction, especially via reward-cap asymmetry
- Insurance/distribution edge cases concentrate risk in last-claimant or residual-balance handling

## Useful Context
- Audit scope is effectively one Solidity file, so cross-function interactions inside `Contract.sol` matter more than cross-file integration
- Highest-signal review areas have been externally callable functions and mutation sites for pools, rewards, and per-round user accounting
- Durable pattern so far: issues cluster around state transitions between accrual and withdrawal, and between one round/user-status state and the next
