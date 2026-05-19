# Audit Report

**Total findings:** 1

## High (1)

### F-001: Full-balance NFT enumeration makes claims unscalable and lets attackers dust wallets into permanent out-of-gas failure

**Confidence:** high | **Locations:** `onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:103, onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:110, onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:112, onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:120, onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:129, onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:150, onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:153, onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:160, onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/contracts/AirdropGrapesToken.sol:167, onchain_auto/0x025c6da5bd0e6a5dd1350fda9e3b6a614b205a1f/@openzeppelin/contracts/token/ERC721/ERC721.sol:150`

`claimTokens()` first calls `getClaimableTokenAmountAndGammaToClaim()` and then re-enumerates the caller's Alpha, Beta, and Gamma holdings again to mark claims, resulting in six unbounded `tokenOfOwnerByIndex` loops over the caller's full balances. Because plain ERC721 `transferFrom` can send tokens to an EOA without recipient consent, an attacker can dust a victim with many low-value or already-claimed NFTs from the eligible collections until `claimTokens()` always exceeds the block gas limit.

**Impact:** Victims and sufficiently large legitimate holders can be unable to complete `claimTokens()` during the finite claim window, permanently losing their GRAPES allocation. The issue is permissionless because the attacker only needs transferable NFTs from the configured collections.

**Paths:**

- Attacker accumulates many eligible Alpha/Beta/Gamma NFTs, including already-claimed ones whose airdrop rights are exhausted but which still increase loop cost.

- Attacker sends those NFTs to the victim using ERC721 `transferFrom`, which does not require the EOA recipient to opt in.

- When the victim calls `claimTokens()`, the contract performs six full enumerations across the victim's balances and runs out of gas before transferring GRAPES.

- Because claims cannot be processed incrementally or by token ID, the victim can remain unable to claim until the window expires.

*Round 1 | Agents: codex_1, opencode_1*

---
