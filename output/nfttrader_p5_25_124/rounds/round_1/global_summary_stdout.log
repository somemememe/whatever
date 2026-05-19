# Global Audit Memory

## Scope Touched
- `0xc310e760778ecbca4c65b6c559874757a4c4ece0/contracts/BatchSwap.sol` - dominant focus; recurring concern around escrow/state consistency across create/close/cancel flows, external asset-transfer branches, and payout handling
- `BatchSwap.sol` swap bookkeeping (`swapMatch`, `swapList`, `nftsOne`, `nftsTwo`) - index/ID coherence and cross-user asset accounting remained a key direction
- `BatchSwap.sol` token/bridge routing (`typeStd`, custom bridge paths, Punk-related routing) - user-selected transfer path correctness and escrow enforcement were repeatedly scrutinized
- `BatchSwap.sol` settlement/cancellation paths - ERC20/ETH payout behavior, unchecked transfer outcomes, and reentrancy around cancellation were persistent themes
- `@openzeppelin/contracts/utils/Counters.sol` - briefly checked as supporting context only; no durable issue signal

## Issue Directions Seen
- Escrow integrity depends heavily on consistent swap indexing and linkage between per-swap records and NFT arrays
- User-influenced asset-standard or bridge-path selection can create mismatches between intended escrow semantics and actual transfer behavior
- External token payment handling is fragile where ERC20 return values are not enforced
- Cancellation/settlement logic exposes reentrancy and state-finalization ordering risk
- ETH payout design is sensitive to `transfer`-style assumptions and can strand value on incompatible recipients
- Admin/configuration and PunkProxy-adjacent surfaces were explored but produced weaker signals than core escrow/accounting paths

## Useful Context
- Audit attention was overwhelmingly concentrated in `BatchSwap.sol`; non-`BatchSwap.sol` scope remains lightly explored
- Cross-agent overlap was strongest on payout safety and ERC20 handling; broader design/admin concerns saw less consensus
- Durable retained signal is centered on escrow/accounting correctness and payout mechanics rather than library-level defects or generic governance concerns
