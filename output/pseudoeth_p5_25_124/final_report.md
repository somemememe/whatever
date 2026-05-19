# Audit Report

**Total findings:** 3

## Medium (2)

### F-001: Direct pair interactions are unsafe when deposits or swap inputs are prefunded in a separate transaction

**Confidence:** medium | **Locations:** `0x2033b54b6789a963a02bfcbd40a46816770f1161/Contract.sol:405, 0x2033b54b6789a963a02bfcbd40a46816770f1161/Contract.sol:409, 0x2033b54b6789a963a02bfcbd40a46816770f1161/Contract.sol:429, 0x2033b54b6789a963a02bfcbd40a46816770f1161/Contract.sol:435, 0x2033b54b6789a963a02bfcbd40a46816770f1161/Contract.sol:454, 0x2033b54b6789a963a02bfcbd40a46816770f1161/Contract.sol:471`

`mint`, `burn`, and `swap` settle against the pair's current balances rather than tracking which address supplied the pending tokens or LP shares. If a user or integrator transfers assets to the pair and completes the corresponding call in a later transaction, any third party can call the matching function first and consume that pending balance delta.

**Impact:** Unsafe direct integrations can lose the full value of prefunded liquidity deposits, LP redemptions, or swap inputs to frontrunners. The issue is narrower than a generic reserve drain because it depends on non-atomic direct use of the pair rather than router-mediated atomic flows.

**Paths:**

- A user transfers `token0` and `token1` to the pair, intending to call `mint` later; an attacker calls `mint(attacker)` first and receives the LP shares created from the victim's deposit.

- A user transfers LP tokens to the pair, intending to call `burn` in a second transaction; an attacker calls `burn(attacker)` first and redeems the underlying assets.

- A user prefunds swap input tokens to the pair address, then submits `swap` separately; an attacker calls `swap(..., attacker, ...)` first and captures output against the victim's input balance delta.

*Round 1 | Agents: codex_1*

---

### F-003: `initialize` can be called repeatedly and accepts invalid token addresses

**Confidence:** high | **Locations:** `0x2033b54b6789a963a02bfcbd40a46816770f1161/Contract.sol:356, 0x2033b54b6789a963a02bfcbd40a46816770f1161/Contract.sol:361, 0x2033b54b6789a963a02bfcbd40a46816770f1161/Contract.sol:362, 0x2033b54b6789a963a02bfcbd40a46816770f1161/Contract.sol:363, 0x2033b54b6789a963a02bfcbd40a46816770f1161/Contract.sol:364`

`initialize` only checks `msg.sender == factory`. It does not enforce one-time initialization and does not validate that the token addresses are non-zero and distinct, so the factory can overwrite `token0`/`token1` after deployment or configure an invalid pair.

**Impact:** A malicious or compromised factory can brick a live pair, strand existing assets by repointing the contract at different tokens, or configure unusable token addresses that break core operations.

**Paths:**

- After liquidity is added, the factory calls `initialize` again with different token addresses, causing future `mint`, `burn`, `swap`, `skim`, and `sync` calls to operate on the new assets while balances of the original assets remain stranded in the pair.

- The factory initializes or reinitializes the pair with `address(0)` or the same token on both sides, causing transfer/balance operations to revert or otherwise making the pool unusable.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-004: Permissionless `skim` lets third parties capture rebases, reflections, and stray transfers

**Confidence:** high | **Locations:** `0x2033b54b6789a963a02bfcbd40a46816770f1161/Contract.sol:485, 0x2033b54b6789a963a02bfcbd40a46816770f1161/Contract.sol:488, 0x2033b54b6789a963a02bfcbd40a46816770f1161/Contract.sol:489`

`skim` is callable by anyone and transfers every balance surplus above the stored reserves to an arbitrary recipient. Any value that appears in the pair without being incorporated into reserves is therefore publicly sweepable.

**Impact:** Accidental direct transfers and value accrual from rebasing or reflection-style tokens can be stolen by third parties instead of benefiting LPs or the original sender.

**Paths:**

- A positive rebase or reflection credits the pair contract while reserves remain unchanged; an attacker calls `skim(attacker)` and withdraws the entire surplus.

- A user mistakenly transfers tokens directly to the pair address; before anyone calls `sync` or otherwise accounts for them, an attacker calls `skim` and takes the excess.

*Round 1 | Agents: codex_1, opencode_1*

---
