# Global Audit Memory

## Scope Touched
- `Roar.sol` — primary attention has centered on `EmergencyWithdraw()`, especially access control, timestamp-gate arithmetic, and withdrawal amount/recipient behavior
- `EmergencyWithdraw()` flow — strongest issue surface so far; combines delayed unlock logic with asset outflow and fixed-amount balance handling

## Issue Directions Seen
- Permissionless emergency-withdraw execution after a preset time gate, enabling full drain behavior once unlocked
- Withdrawal accounting uses hard-coded token amounts rather than actual balances, creating residue/stranding risk for ROAR and LP assets
- Time-gate arithmetic/obfuscation around the emergency path is a recurring point of suspicion, even where framed as opaque rather than separately retained
- Recipient handling via `tx.origin` was investigated as a misuse direction, though not retained as a finding

## Useful Context
- Audit attention so far is narrowly concentrated on a single contract and mostly one withdrawal path rather than the broader `Roar.sol` surface
- The most durable cross-round pattern is the combination of weak emergency-withdraw authorization with brittle payout logic
- No other Solidity files or alternative contract flows have yet accumulated meaningful cross-round context
