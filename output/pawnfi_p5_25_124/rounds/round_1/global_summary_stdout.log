# Global Audit Memory

## Scope Touched
- `contracts/ApeStaking.sol`: dominant audit surface; issues cluster around NFT-backed staking/lending lifecycle, ownership and authorization drift, batch state contamination, and reward/accounting correctness
- `contracts/ApeStakingStorage.sol`: supporting state layout/context for depositor, staking, and per-position accounting assumptions
- `contracts/interfaces/IApeCoinStaking.sol`, `contracts/interfaces/IPTokenApeStaking.sol`, `contracts/interfaces/ITokenLending.sol`: key external coupling surfaces for stake/unstake, reward flow, pToken/iToken accounting, and lending integration behavior
- `contracts/interfaces/IApePool.sol`, `contracts/interfaces/INftGateway.sol`: secondary context around pool/gateway integration, with less direct issue concentration

## Issue Directions Seen
- Ownership / authorization drift around depositor, owner, staker, and paired-position semantics, especially after state changes or partial withdrawals
- Reward accounting inconsistencies on partial unstake/claim paths and health-check calculations tied to reward-rate range selection
- Per-NFT share allocation precision and floor-rounding effects causing residual or stranded value
- Cross-call state-sync risks where internal accounting assumes successful external staking/lending side effects
- External integration handling weaknesses, especially ignored or weakly-checked return values from lending mint flows
- Batch or multi-NFT processing paths as a recurring source of mode contamination and position-mixing bugs

## Useful Context
- Audit attention has been heavily concentrated on `ApeStaking.sol`; interfaces and storage were mostly read to validate assumptions about that contract’s behavior
- The strongest recurring theme is mismatch between logical position ownership and the contract state used to authorize claims, withdrawals, or reward access
- Another repeated pattern is value becoming stuck or misassigned through partial operations: partial unstake, split allocation, and batched withdrawal handling
- Generic admin/config, approval, and input-validation surfaces were explored but were less durable than the ownership/accounting/state-sync directions above
