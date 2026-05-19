# Global Audit Memory

## Scope Touched
- `contracts/core/Vault.sol`: main audit surface so far; repeated attention on deposit/withdraw share accounting, asset-handling edge cases, and privileged share-mint/configuration paths
- `contracts/interfaces/IController.sol`: relevant dependency boundary for vault behavior, especially around controller-mediated asset movement and trust assumptions
- `contracts/interfaces/IVault.sol`: supporting interface context for vault semantics
- `contracts/utils/TransferHelper.sol`: supporting context for transfer behavior and failure handling
- OpenZeppelin `Initializable.sol`: minor contextual read only; no durable issue direction retained from it

## Issue Directions Seen
- Share-accounting edge cases in `Vault.sol` are the strongest recurring direction, especially zero-share mint/burn outcomes and conversion math around deposits and withdrawals
- Deposit pricing/order-of-operations is a recurring concern, including post-transfer pricing effects that can under-mint incoming users
- Privileged or semi-privileged minting/configuration surfaces around `subStrategy` and related vault wiring remain important attention areas
- Asset-model inconsistencies around ETH vs ERC20 handling surfaced repeatedly, including acceptance of excess ETH and deposit-path mismatch risks
- Controller interaction is a notable dependency surface, but retained reasoning has stayed limited to vault-side behavior that is provable without assuming specific controller semantics

## Useful Context
- Audit attention has been heavily concentrated in `Vault.sol`; other files have mostly served as context for understanding vault behavior
- Cross-round durable observations currently skew toward concrete vault-local logic bugs rather than broader architectural trust concerns
- Retained findings so far cluster around accounting correctness, mint/burn invariants, and edge-case input handling in deposit/withdraw flows
