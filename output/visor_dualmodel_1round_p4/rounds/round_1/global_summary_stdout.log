# Global Audit Memory

## Scope Touched
- `contracts/RewardsHypervisor.sol` — persistent center of review, especially `deposit()` share pricing, first-mint initialization, contract-vs-EOA deposit paths, and the `deposit()`/`withdraw()` accounting relationship
- `contracts/interfaces/IVisor.sol` — relevant because Hypervisor trust in visor-mediated transfers appears central to unbacked-share minting risk
- `contracts/vVISR.sol` — repeatedly reviewed as adjacent staking/share logic and access-control surface, but not a retained issue source so far
- `FlawVerifier.sol` — used to validate exploit mechanics and separate distinct root causes in share-accounting failures
- OpenZeppelin ERC20 / `SafeERC20` / snapshot / EIP712 / ECDSA utilities — referenced mainly as supporting context around transfer and authorization assumptions

## Issue Directions Seen
- Share minting in `RewardsHypervisor` repeatedly trends toward accounting mismatches: minted shares can depend on requested or assumed VISR rather than reliably confirmed received assets
- The contract deposit path remains a durable risk area because visor-mediated transfers and authorization assumptions can allow fake or short-paying deposits
- First-depositor / bootstrap-state behavior is a recurring theme, with pre-seeded assets and initial share supply creating capture or drain opportunities
- Donation-driven price manipulation is a recurring direction: direct VISR transfers can distort share price and under-mint later deposits
- The EOA deposit path also shows an authorization direction, where existing user approvals to the Hypervisor can be turned into attacker-benefiting deposits
- Broader `vVISR` access-control and generic withdraw-side concerns were explored, but cross-round signal remains materially weaker than the `RewardsHypervisor.deposit()` cluster

## Useful Context
- Cross-round attention is heavily concentrated on `RewardsHypervisor`, especially `deposit()`, with `withdraw()` and `vVISR` receiving secondary review
- The strongest retained patterns are not isolated bugs but a family of share-accounting and authorization failures around how deposits are sourced, valued, and credited
- Review effort repeatedly distinguished similar-looking theories into separate root causes: fake-visor deposits, bootstrap capture, donation-induced mispricing, and approval-powered third-party pulls
- `FlawVerifier.sol` served as important corroboration for exploit causality rather than as an issue source itself
