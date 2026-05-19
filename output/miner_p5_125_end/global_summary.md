# Global Audit Memory

## Scope Touched
- `0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol`:
  hybrid ERC20/ERC721 implementation remains the central audit surface, especially the overloaded `approve`, `transferFrom`, `safeTransferFrom`, ownership helpers, and transfer lifecycle hooks
- `_update` / `_afterTokenTransfer` path in `Contract.sol`:
  recurring hotspot for burn-mint accounting and transfer-delay side effects during single ERC20 moves that also shift NFT units

## Issue Directions Seen
- ERC20/ERC721 semantic overloading repeatedly creates ambiguity between fungible allowances and per-token approvals
- NFT-style transfer paths appear capable of unintended ERC20 balance effects, including double debiting during mixed `transferFrom` handling
- Approval lifecycle handling is fragile in the hybrid design, including stale `getApproved` state persisting across safe-transfer paths
- Unit/ID interpretation remains a persistent risk area where small ERC20 approval values can be treated as NFT approvals
- Transfer restrictions layered onto hybrid accounting, especially max-wallet and transfer-delay logic, are a recurring source of edge-case breakage

## Useful Context
- Audit attention has stayed concentrated on a single contract rather than spreading across multiple files
- Cross-round convergence is strongest around the mixed approval and transfer interface surface, suggesting this is the contract’s dominant risk cluster
- Broader accounting and restriction logic around `_update` was investigated less directly than the approval/transfer surface but continues to look structurally important
- Retained findings so far consistently stem from the contract’s attempt to share one interface layer across fungible and non-fungible behaviors
