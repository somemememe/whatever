# Audit Report

**Total findings:** 4

## High (2)

### F-001: ERC721-style `transferFrom` debits two NFT-worths of ERC20 balance for one NFT transfer

**Confidence:** high | **Locations:** `0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1903, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1917, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1921, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1340, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1343`

When `value < _nextTokenId()`, `transferFrom` treats `value` as an NFT id, performs `_transfer(from, to, tokensPerNFT, false)`, then calls `_safeTransferFrom`, which performs a second `_transfer(from, to, tokensPerNFT, false)`. One NFT transfer therefore moves only one NFT id but debits and credits `2 * tokensPerNFT` fungible units.

**Impact:** Any owner, approved operator, or stale per-token approvee using the NFT branch of `transferFrom` can overcharge the sender by an extra whole-NFT worth of ERC20 balance. This breaks the ERC20/NFT backing invariant, gifts the recipient extra fungible value, and can strand the sender's remaining NFTs behind insufficient ERC20 balance. Holders with only one NFT-worth of balance cannot use this `transferFrom` path at all because the second debit reverts.

**Paths:**

- A holder owns NFT `id` and at least `2 * tokensPerNFT` fungible balance

- An authorized caller invokes `transferFrom(from, to, id)`

- The call transfers NFT `id` once but transfers `tokensPerNFT` fungible units twice

*Round 1 | Agents: codex_1*

---

### F-002: Per-token approvals survive `safeTransferFrom` and `safeBatchTransferFrom`, leaving a latent theft backdoor on transferred NFTs

**Confidence:** high | **Locations:** `0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1087, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1280, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1297, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1340, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1401, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1919`

Single-token approvals in `getApproved` are only cleared in the NFT branch of `transferFrom` via `delete getApproved[value]`. The `safeTransferFrom` and `safeBatchTransferFrom` paths move ownership in `_safeTransferFrom` / `_safeBatchTransferFrom` without clearing `getApproved[id]`, so a prior approvee remains authorized after the token changes owner.

**Impact:** NFTs transferred through the safe-transfer paths can carry hidden stale approvals from previous owners. Those stale approvees can later call the NFT `transferFrom` path to take the token from a future owner once that owner has enough fungible balance to satisfy this contract's broken double-debit transfer logic, creating a latent theft backdoor on listed or escrowed NFTs.

**Paths:**

- Alice calls `approve(mallory, id)` for NFT `id`

- Alice transfers `id` to Bob through `safeTransferFrom` or `safeBatchTransferFrom`

- `getApproved[id]` is still `mallory`, and Mallory can later call `transferFrom(Bob, mallory, id)` once Bob's balance is high enough for the NFT branch to succeed

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-003: Small ERC20 approvals are reinterpreted as NFT approvals

**Confidence:** high | **Locations:** `0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1884, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1886, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1892, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1903, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1912`

`approve(spender, value)` switches behavior on `value < _nextTokenId() && value > 0`. In that range it does not create an ERC20 allowance; it instead requires the caller to own NFT `value` and then sets `getApproved[value] = spender`, treating the numeric amount as an NFT id.

**Impact:** A malicious dApp or integrator can request what looks like a small ERC20 approval and instead obtain control over a specific NFT id. Once the attacker has `getApproved[id]`, they can use the NFT branch of `transferFrom` to seize that token whenever the victim has enough fungible balance for that broken transfer path to execute.

**Paths:**

- The victim is prompted to sign `approve(attacker, id)` as if it were a small ERC20 approval

- The contract stores `getApproved[id] = attacker` instead of an ERC20 allowance

- The attacker later invokes `transferFrom(victim, attacker, id)` to take the NFT when the victim's balance satisfies the NFT transfer path

*Round 1 | Agents: codex_1, opencode_1*

---

### F-004: Transfer-delay hook self-reverts ERC20 transfers that both burn and mint NFTs in one transaction

**Confidence:** high | **Locations:** `0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1566, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1677, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1681, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1957, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1961, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:1973, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:2107, 0xe77ec1bf3a5c95bfe3be7bdbacfe3ac1c7e454cd/Contract.sol:2110`

Normal ERC20 transfers run `_update(..., mint=true)`, which may call `_burnBatch` for the sender and `_mintWithoutCheck` for the recipient in the same transaction. Both helpers invoke `_afterTokenTransfer`, and the `ERC_X` override enforces `transferDelay` by requiring `delayTimer[tx.origin] < block.number` and then immediately setting `delayTimer[tx.origin] = block.number`. If a transfer both burns at least one NFT from `from` and mints at least one NFT to `to`, the burn hook consumes the per-block slot and the subsequent mint hook reverts in the same transaction.

**Impact:** While `transferDelay` is enabled (the default), a wide class of non-whitelisted ERC20 transfers and trades become permissionlessly unexecutable whenever both sides cross a `tokensPerNFT` boundary in the same transfer. This creates a realistic launch-phase denial of service for common whole-token transfers and trades.

**Paths:**

- `transferDelay` remains enabled and both participants are non-whitelisted

- An ERC20 `transfer` or ERC20 `transferFrom` causes `tokens_to_burn > 0` for the sender and `tokens_to_mint > 0` for the recipient

- `_burnBatch` updates `delayTimer[tx.origin]` via `_afterTokenTransfer`, then `_mintWithoutCheck` immediately hits the same check and the entire transfer reverts

*Round 1 | Agents: *

---
