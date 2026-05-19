# Global Audit Memory

## Scope Touched
- `contracts/RewardsHypervisor.sol` — primary audit surface so far; recurring concern is deposit/share accounting, depositor authorization, and trust boundaries around asset sourcing
- `contracts/vVISR.sol` — reviewed as supporting context around staking/share interactions, but no retained cross-round issue direction beyond dependency context
- `contracts/interfaces/IVisor.sol` — relevant to assumptions about contract-based deposits and whether caller-controlled visor behavior can bypass backing checks
- OpenZeppelin ERC20/snapshot/permit helpers (`ERC20.sol`, `ERC20Snapshot.sol`, `SafeERC20.sol`, `ERC20Permit.sol`, `EIP712.sol`, `ECDSA.sol`, `Address.sol`, `Arrays.sol`, `SafeMath.sol`, `Ownable.sol`) — mainly inheritance/library context; useful for transfer, approval, and snapshot semantics rather than as independent issue centers

## Issue Directions Seen
- `RewardsHypervisor.deposit` is the dominant risk area: share minting often appears insufficiently tied to assets actually received or legitimately sourced
- Authorization/trust-model weaknesses around deposits are a recurring theme, especially when the depositor, funding source, and minted-share recipient can diverge
- Contract-based depositor flows are especially sensitive because `IVisor` assumptions may let attacker-controlled contracts simulate backing or bypass intended trust guarantees
- Initialization / first-deposit pricing remains a strong direction: pre-seeded assets can distort the initial exchange rate and let early actors capture value
- Broader ERC20 math/callback/library-footgun ideas were explored, but the durable pattern is still accounting integrity at the hypervisor deposit boundary

## Useful Context
- Cross-round attention is heavily concentrated on `RewardsHypervisor` rather than the wider codebase
- Retained issues consistently cluster around the same core theme: minted shares can become disconnected from real economic backing
- The most durable audit framing so far is to treat deposit logic as a combination of accounting problem, authorization problem, and external-trust problem
- `vVISR` and inherited OpenZeppelin surfaces matter mostly as context for understanding consequences and invariants around the hypervisor, not as primary finding generators so far
