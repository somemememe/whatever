# Global Audit Memory

## Scope Touched
- `contracts/DN404Reflect.sol` - central surface for reflection accounting, excluded/include state transitions, and base-side DN404 transfer behavior
- `contracts/DN404Mirror.sol` - mirror/base initialization handshake and ERC721-side transfer semantics remain important
- `contracts/DeezNutz.sol` - token-specific routing of DN404 flows, ownership setup, trading controls, and NFT-linked transfer paths

## Issue Directions Seen
- DN404 base/mirror linkage and initialization is a core recurring risk area, including permanent misbinding/front-run style setup failures
- ERC20/ERC721 boundary behavior is a repeated source of edge cases, especially whole-NFT-unit transfers interacting differently from taxed ERC20 paths
- Reflection bookkeeping remains a persistent direction, particularly around excluded-account accounting and state transitions
- Admin/control-plane logic keeps surfacing: constructor ownership initialization, renounce behavior, and include/exclude control edge cases
- Trading restriction and router/NFT path bypass themes appeared repeatedly around alternative transfer entrypoints

## Useful Context
- Most cross-round attention converged on the three-core-contract cluster: `DeezNutz`, `DN404Reflect`, and `DN404Mirror`
- `DN404Reflect.sol` has drawn the highest sustained scrutiny, with `DeezNutz.sol` and `DN404Mirror.sol` as secondary but repeatedly relevant surfaces
- Underexplored but repeatedly suspicious areas include `DeezNutz.transferFrom`, `DeezNutz._transferFromNFT`, and excluded-account reflection paths
- Durable retained themes from the first round include mirror-link hijackability, NFT-unit tax bypass, broken re-inclusion of excluded accounts, and `tx.origin`-based constructor ownership assignment
