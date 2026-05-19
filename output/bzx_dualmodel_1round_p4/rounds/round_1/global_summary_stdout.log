# Global Audit Memory

## Scope Touched
- `onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol` — primary audit surface; repeated focus on `borrow`, `marginTrade`, `mint`, `_verifyTransfers`, `_internalTransferFrom`, `tokenPrice`, and later admin/settings logic around authorization, accounting, pricing, and transfer flow coupling
- `onchain_auto/0xb983e01458529665007ff7e0cddecdb74b967eb6/Contract.sol` — secondary proxy/fallback surface; attention centered on ETH-handling behavior, especially fallback acceptance under constrained gas

## Issue Directions Seen
- Existing-loan wrapper paths repeatedly look sensitive to caller-supplied borrower/trader identities and authorization binding
- Deposit/collateral accounting versus actual received amount is a durable theme, especially for fee-on-transfer or otherwise non-standard token behavior
- Core transfer/accounting paths appear coupled to external interest or settlement queries, creating a recurring DoS / liveness direction
- `marginTrade` value flow has been a consistent hotspot, particularly around excess ETH forwarding and mismatches between declared and actual native-value use
- Price-related logic (`tokenPrice`, oracle validation) keeps resurfacing as a promising direction, though broad manipulation theories were not retained
- Admin/external-call surfaces such as settings updates and flash-borrow style hooks were explored as control/reentrancy directions, but remain less substantiated than fund-flow issues
- Proxy fallback ETH handling is a persistent concern, with low-gas acceptance potentially stranding native ETH

## Useful Context
- Cross-round attention is heavily concentrated on the main `0x9e13...` contract; the proxy contract is relevant but comparatively underexplored
- Stronger retained themes come from concrete line-level fund-flow review rather than broad control-surface hypothesis generation
- Recurrent hotspots cluster around entrypoints that mix authorization, token transfer accounting, pricing, and native ETH forwarding
- The late-file admin/settings region has drawn suspicion without durable confirmation, so it remains contextual rather than central
- Broad transfer/price/oracle concerns have been repeatedly narrowed into more specific supported variants instead of standing as generic issues
