# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: Vault NFTs can be bought for the same flat fee regardless of collection or value

**Confidence:** high | **Locations:** `0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1052, 0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1067, 0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1073, 0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1083, 0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1099`

`buyNFTs()` lets callers name arbitrary ERC721/ERC1155 assets currently held by the contract, transfers them out, and only charges a count-based ETH fee plus a fixed `buyNftFeeJay` burn per unit. There is no whitelist, per-collection pricing, provenance tracking, or valuation check tying redemption cost to the NFT's actual market value.

**Impact:** Any valuable NFT deposited into the vault, whether through `buyJay()` or an accidental direct transfer, can be stolen for the same tiny flat fee used for worthless NFTs. This is direct loss of vault inventory and can wipe out NFT backing for the token.

**Paths:**

- A user deposits a valuable NFT into the contract through `buyJay()` or transfers it there directly.

- An attacker acquires only the fixed ETH and JAY fees required by `buyNFTs()`.

- The attacker calls `buyNFTs()` with that NFT's contract address and token id and receives the asset at the flat protocol fee.

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-002: `buyJay()` accepts zero NFTs but still gives the higher 97% mint rate

**Confidence:** high | **Locations:** `0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1111, 0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1118, 0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1131, 0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1142, 0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1200, 0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1204`

`buyJay()` never requires that any NFT be supplied. If all NFT arrays are empty then `total` stays zero, the fee check trivially passes, and the function still mints `ETHtoJAY(msg.value) * 97 / 100`, which is materially better than `buyJayNoNFT()`'s 85% path.

**Impact:** Any buyer can bypass the intended no-NFT fee schedule and mint more JAY for the same ETH than the protocol appears to allow. This dilutes existing holders and also makes it cheaper to accumulate JAY for subsequent NFT withdrawals.

**Paths:**

- After `startJay()`, a user calls `buyJay([], [], [], [], [])` with ETH.

- Because `total == 0`, the NFT-fee requirement passes without transferring any NFT.

- The caller receives the 97% mint path instead of the 85% `buyJayNoNFT()` path.

*Round 1 | Agents: codex_1*

---

### F-003: Reentrant `sell()` calls over-withdraw ETH by pricing later sells before prior dev fees leave the pool

**Confidence:** high | **Locations:** `0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1188, 0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1189, 0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1191, 0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1193`

`sell()` computes the ETH quote, burns JAY, then sends ETH to `msg.sender` before paying the dev fee. A contract seller can reenter `sell()` from its fallback during the first payout, and each nested quote is computed from a balance that still includes dev fees owed by outer frames. This lets the attacker capture value that should have been excluded from subsequent pricing.

**Impact:** A large holder can withdraw more ETH than intended and bypass a meaningful portion of protocol fees, leaving the reserve with less backing than under intended non-reentrant execution.

**Paths:**

- An attacker contract accumulates JAY and calls `sell(chunk1)`.

- When the first `msg.sender.call` sends ETH, the attacker's fallback reenters `sell(chunk2)` before the outer `dev.call` executes.

- The nested sale is quoted against an inflated pool balance because prior dev fees are still sitting in the contract, so the attacker receives excess ETH across the reentrant sequence.

*Round 1 | Agents: codex_1, opencode_1*

---

## Low (1)

### F-005: Burning the final JAY supply reverts because the post-burn price event divides by zero

**Confidence:** high | **Locations:** `0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1073, 0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1076, 0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1196, 0xf2919d1d80aff2940274014bef534f7791906ff2/Contract.sol:1227`

Both burn paths emit `Price` by calling `JAYtoETH(1e18)` after `_burn()`. If that burn reduces `totalSupply()` to zero, `JAYtoETH()` divides by zero and reverts the entire transaction.

**Impact:** The final full redemption cannot complete, so the system cannot fully unwind cleanly. Some residual JAY supply and/or backing ETH must remain trapped instead of allowing a complete exit.

**Paths:**

- A holder attempts the last full `sell()` or final JAY-burning `buyNFTs()` redemption.

- `_burn()` reduces `totalSupply()` to zero.

- The subsequent `emit Price(... JAYtoETH(1e18))` triggers division by zero and reverts the whole transaction.

*Round 1 | Agents: codex_1, opencode_1*

---
