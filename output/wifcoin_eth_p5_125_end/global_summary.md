# Global Audit Memory

## Scope Touched
- `0xa1ce40702e15d0417a6c74d0bab96772f36f4e99/contracts/WIFStaking.sol`: central audit surface so far; repeated focus on reward-claim, unstake, emergency/penalty withdrawal, and token-transfer paths
- `claimEarned`: dominant hotspot for maturity gating, repeat-claimability, internal reward accounting, and possible interaction-safety concerns
- `unstake`: tied closely to reward settlement and stale-entry handling; overlap with double-payment / liability accounting concerns
- `penaltyWithdraw` and owner/admin withdrawal paths: direction around owner access to pooled assets versus outstanding user liabilities
- `earnedToken` and `emergencyWithdraw`: secondary but recurring attention on reward-model correctness and exit/penalty behavior

## Issue Directions Seen
- Reward lifecycle is the main recurring theme: early reward release, repeatable claims, and the same reward being reachable through multiple paths
- Solvency/liability separation is a persistent direction: contract-admin withdrawals may not preserve assets needed for user principal and rewards
- Token-flow safety remains relevant: raw ERC20 calls may let internal accounting move ahead of actual token movement on non-standard tokens
- Several lower-confidence directions recurred without retention: `claimEarned` accounting totals, reentrancy hardening, stale zero-amount stake records, and emergency-withdraw semantics

## Useful Context
- Cross-round attention is highly concentrated in a single staking contract rather than spread across the codebase
- Both agents independently converged on `claimEarned` as the highest-risk area, especially around lock enforcement and reward replay
- Audit interest naturally clusters around interactions between `claimEarned`, `unstake`, and admin withdrawal functions rather than isolated function-local bugs
- Broader hygiene/admin concerns appeared, but durable signal so far is strongest in reward accounting and asset-liability integrity
