# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: Any allowlisted address can mint the entire public allocation in a single free claim

**Confidence:** high | **Locations:** `onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1189, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1192, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1196, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1199, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1204`

`WhiteListMint` only checks that `msg.sender` has not minted before via `_numberMinted(msg.sender) < 1`, but it never caps `chosenAmount` to 1 and the Merkle leaf contains only the address, not an allowed quantity. A single valid allowlisted address can therefore choose any `chosenAmount` up to the remaining non-reserved supply and receive all of it in its first claim.

**Impact:** One allowlisted participant can drain the full public/whitelist allocation for free, permanently excluding the rest of the allowlist and breaking the intended distribution.

**Paths:**

- An allowlisted address submits a valid Merkle proof and calls `WhiteListMint(proof, maxsupply - reserve - totalSupply())`, receiving the entire remaining non-reserved allocation in one transaction.

*Round 1 | Agents: codex_1, opencode_1*

---

## High (1)

### F-002: Owner can inflate supply beyond `maxsupply` by resetting `reserve` and minting again

**Confidence:** high | **Locations:** `onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1163, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1164, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1180, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1181, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1182, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1183`

The contract treats `reserve` as a mutable counter rather than a fixed remaining allocation. `setReserve` can reset it to any value up to `maxsupply`, and `mintReservedTokens` only checks `quantity <= reserve`; it never enforces `totalSupply() + quantity <= maxsupply`. After the collection has already minted out, the owner can restore `reserve` and mint additional NFTs.

**Impact:** The advertised hard cap can be violated, diluting holders and allowing the owner to mint supply beyond the stated maximum.

**Paths:**

- After 1221 NFTs have already been minted, the owner calls `setReserve(100)` and then `mintReservedTokens(100)`, pushing total minted supply above `maxsupply`.

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (1)

### F-003: Reentrant `_safeMint` can reuse a stale `_currentIndex` and corrupt ERC721A accounting

**Confidence:** medium | **Locations:** `onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:819, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:829, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:832, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:837, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:841, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:849, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1183`

`_mint` records balances and initial ownership, then performs external `onERC721Received` callbacks inside the mint loop before advancing `_currentIndex`. If the receiver is a contract that can reenter a mint path, the nested mint reuses the old `startTokenId` because `_currentIndex` is still stale, causing duplicate token IDs/events and inconsistent balance, ownership, and `totalSupply` accounting.

**Impact:** A contract receiver can corrupt collection state during minting, leading to duplicate mint events, phantom tokens, incorrect balances, and broken supply/accounting. In practice this is reachable through `mintReservedTokens` if ownership is held by an ERC721Receiver-compatible contract.

**Paths:**

- A contract owner implementing `onERC721Received` calls `mintReservedTokens(2)`.

- During the callback for the first token, it reenters `mintReservedTokens(1)` before the outer call updates `_currentIndex`.

- Both mints use the same `startTokenId`, leaving duplicated events and inconsistent ownership/supply state when the calls return.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-004: Owner can arbitrarily change metadata and reversibly hide revealed NFTs

**Confidence:** high | **Locations:** `onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1155, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1170, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1176, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1221, onchain_auto/0xb84cbaf116eb90fd445dd5aeadfab3e807d2cbac/Contract.sol:1225`

The owner can change both the hidden metadata URI and the revealed base URI at any time, and `reveal()` is reversible because it toggles the boolean instead of making reveal one-way. There is no freeze or irrevocable reveal mechanism.

**Impact:** Collectors have no assurance that purchased NFTs will keep the promised metadata; the owner can swap metadata after sale or hide revealed NFTs again, enabling a classic metadata rug.

**Paths:**

- After minting, the owner calls `setBaseURI(...)` to point token metadata at different content.

- The owner later calls `reveal()` again, flipping `revealed` back to `false` so all tokens return the placeholder URI from `notRevealedUri`.

*Round 1 | Agents: codex_1, opencode_1*

---
