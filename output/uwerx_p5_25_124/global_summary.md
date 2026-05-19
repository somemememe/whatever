# Global Audit Memory

## Scope Touched
- `0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol`: dominant focus across rounds; sell-path logic around `uniswapPoolAddress` and admin-settable addresses drive most risk
- `transferFrom` / `_spendAllowance`: allowance handling is entangled with sell-path burn behavior and may not bound total sender loss on pool-directed transfers
- `_transfer` / `_burn`: special pool path appears to change real token debits versus nominal `amount`, including exact-balance edge cases and event/accounting divergence
- `setUniswapPoolAddress`: owner-controlled retargeting point for the special transfer path
- `setMarketingWallet`: reviewed as part of privileged-address configuration, but not yet tied to a durable exploit path

## Issue Directions Seen
- Special handling when `to == uniswapPoolAddress` creates a recurring direction around broken transfer accounting on sells
- Allowance consumption versus extra burn/debit remains a core direction, especially where approved amount and actual sender loss can diverge
- Exact-amount / exact-balance transfer behavior is a recurring stress point for the sell path
- `Transfer` event emissions may not faithfully reflect storage-level balance changes
- Owner-controlled address retargeting is a recurring direction, especially where admin can redirect the broken pool-specific path to arbitrary destinations
- Broader centralization observations were explored, but the durable cross-round signal is strongest where privileged configurability intersects directly with faulty transfer logic

## Useful Context
- Attention has concentrated almost entirely on a single contract and one cluster of logic: pool-directed transfers plus the owner controls that configure that path
- The most durable pattern is not generic admin power, but admin ability to repoint a path that already appears mechanically broken
- Marketing-wallet and no-timelock concerns were examined but have weaker cross-round support than the sell-path/accounting issues
- Cross-agent overlap strongly supports prioritizing semantic mismatches between user-visible transfer amounts, allowance expectations, emitted events, and actual balance deltas
