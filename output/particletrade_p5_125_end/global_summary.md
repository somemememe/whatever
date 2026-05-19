# Global Audit Memory

## Scope Touched
- `contracts/protocol/ParticleExchange.sol` - central audit surface across rounds; attention repeatedly lands on batched payable entrypoints, refinance state rewrites, repayment/settlement, buyback/auction closeout paths, and NFT/lien bookkeeping
- `contracts/interfaces/IParticleExchange.sol` - relevant mainly for understanding exchange flow assumptions exposed by the main protocol contract
- `lib/openzeppelin-contracts/contracts/utils/Multicall.sol` - important because `delegatecall` batching interacts with payable logic and shared `msg.value`

## Issue Directions Seen
- Batched payable calls can reuse a single `msg.value` through `Multicall`, making aggregated value accounting a recurring concern
- Refinance logic is a high-risk state-transition area, especially around lien replacement, aliasing, and collateral/lien association rewrites
- Closeout paths appear to rely on collection-level NFT identity rather than strict token-specific tracking, creating substitution risk across repayment, buyback, auction, and receiver flows
- Auction/liquidation gating remains a meaningful area of interest, though less consistently developed than the value-accounting and collateral-tracking directions

## Useful Context
- Cross-round attention is heavily concentrated in `ParticleExchange.sol`; other files mainly matter as supporting context for its execution model
- Durable risk pattern: financial flows and NFT custody logic are tightly coupled, so bugs tend to arise when state updates, payment handling, and token identity assumptions diverge
- Retained findings so far cluster around three stable themes: shared-value reuse in batched calls, refinance-driven corruption of lien/collateral mapping, and collection-fungible treatment of escrowed NFTs
