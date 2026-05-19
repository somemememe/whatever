# Global Audit Memory

## Scope Touched
- `0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol` — dominant audit surface; repeated attention on `buyNFTs()`, `buyJay()`, `sell()`, pricing helpers, reserve/fee logic, and burn edge cases
- `0xf2919d1d80aff2940274014bef534f7791906ff2/_index.json` — surfaced only for scope mapping
- `0xf2919d1d80aff2940274014bef534f7791906ff2/_etherscan_meta.json` — surfaced only for source metadata

## Issue Directions Seen
- Economic mismatch between NFT-related flows and actual asset value, especially flat-fee redemption from vault inventory
- Preferential mint path abuse in `buyJay()`, including empty-NFT input reaching seller-favored pricing
- Reentrancy and state-ordering risk in `sell()`, tied to reserve-sensitive payout / fee sequencing
- Pricing-helper fragility around terminal supply states, especially division-by-zero after full burn
- Recurrent suspicion around permissionless or reserve-driven `updateFees()` behavior, though not retained as a standalone issue
- Broad generic checks also appeared repeatedly: oracle freshness assumptions, transfer semantics, array validation, and admin/control surfaces

## Useful Context
- Cross-round attention is highly concentrated in a single contract, with both agents repeatedly converging on `sell()` and pricing/burn paths
- The strongest durable pattern is interaction between economic design flaws and reserve-based accounting rather than isolated access-control bugs
- `codex_1` contributed the sharper economic-path analysis; `opencode_1` covered a wider but mostly lower-signal generic checklist
- Manual reasoning supported some conclusions where local PoC execution was incomplete due to Foundry issues
