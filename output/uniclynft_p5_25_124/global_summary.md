# Global Audit Memory

## Scope Touched
- `0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol`: dominant focus across rounds; `PointFarm` deposit/withdraw/emergency-withdraw reward paths, pool accounting, and admin emission/shop configuration are the main risk surface
- `PointFarm` reward minting / ERC1155 receiver flow: callback-facing mint path intersects with user debt updates and reward claiming
- Pool stake accounting based on contract token balance: sensitive to non-standard staking tokens and share solvency assumptions
- Emission/admin setters such as `setMintRules`, `setStartBlock`, `updatePool`, `add`, `setShop`: governance-driven parameters can affect pool settlement behavior and historical reward accounting

## Issue Directions Seen
- Reentrancy around ERC1155 reward minting before reward-debt/accounting updates
- Reward/share insolvency from fee-on-transfer or balance-changing staking tokens when accounting assumes nominal deposited amounts
- Retroactive reward distortion when global emission parameters change without checkpointing untouched pools first
- Repeated attention on withdrawal/emergency-withdraw accounting correctness, though not all candidate theories held up
- Lower-confidence but recurring scrutiny on pool/admin safety checks and initialization/gating behavior

## Useful Context
- Audit attention is concentrated in a single contract, with the staking/reward accounting surface carrying most of the meaningful risk
- The strongest recurring pattern is ordering-sensitive accounting: external reward delivery, pool settlement, and user debt updates interact in ways that can create exploitable mismatches
- Cross-round review split between concrete exploit paths in user reward flows and softer admin/operational correctness checks; the former has produced the durable findings so far
- Late-file view/update functions such as `pendingPoints`, `deposit`, `withdraw`, `emergencyWithdraw`, and `updatePool` are the key junctions for understanding reward behavior across the contract
