# Global Audit Memory

## Scope Touched
- `src/Land/erc721/ERC721BaseToken.sol` — primary hotspot across rounds; transfer, approval, burn, and receiver-check logic repeatedly scrutinized
- `src/Land/erc721/LandBaseToken.sol` — paired hotspot with ERC721 base; quad-specific mint/transfer/regroup behavior and burn-sentinel interactions matter
- `src/Land.sol` — reviewed as the higher-level LAND entry surface, mainly for how it routes into base burn/transfer mechanics
- `contracts_common/src/BaseWithStorage/SuperOperators.sol` — privilege model drew attention, though no merged issue yet
- `contracts_common/src/BaseWithStorage/Admin.sol` — admin-change safety and privileged control assumptions were examined without retained findings
- receiver/interface helpers under `contracts_common/src` — relevant for ERC-165 / safe-transfer validation and contract compatibility edge cases

## Issue Directions Seen
- Unauthorized or weakly gated burn paths affecting ownership and balance accounting
- Burn-state sentinels interfering with later quad regrouping or transfer behavior
- Unsafe quad safe-transfer / receiver validation causing LAND lockup in incompatible contracts
- Approval, super-operator, and privileged-transfer surfaces remain a recurring review direction even without retained issues so far
- Transfer existence checks and edge-case validation around batch/quad operations are a persistent concern area

## Useful Context
- Cross-round attention is concentrated on LAND ERC721 base logic rather than peripheral helpers
- The durable issue cluster is around burn/transfer interactions, especially where single-token ERC721 logic meets quad LAND semantics
- Both agents independently converged on `ERC721BaseToken` and `LandBaseToken`, making those the highest-signal contracts for future review
- Access-control helper contracts were read and considered relevant context, but the strongest retained signals currently come from token-state transition mechanics, not admin plumbing
