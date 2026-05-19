# Audit Report

**Total findings:** 4

## High (1)

### F-001: Pool-directed transferFrom can burn more tokens than the approved allowance

**Confidence:** high | **Locations:** `0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:403, 0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:409, 0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:489, 0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:496, 0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:540`

When `transferFrom(from, uniswapPoolAddress, amount)` is used, the contract spends allowance only for `amount`, then `_transfer` burns an additional `burnAmount` from `from` via `_burn(from, burnAmount)`. Because that extra burn is not covered by `_spendAllowance`, an approved spender can reduce the holder's balance by more than the approved amount.

**Impact:** Any spender or router approved for N tokens can cause the holder to lose N plus the extra burn on each pool-directed transfer. This violates expected ERC20 allowance boundaries and can create unauthorized user loss in integrations that rely on approvals as hard spend caps.

**Paths:**

- A holder approves a spender or router for `N` tokens.

- The spender calls `transferFrom(holder, uniswapPoolAddress, N)`.

- `_spendAllowance` deducts only `N`, but `_transfer` then calls `_burn(holder, burnAmount)`, removing additional balance without additional allowance.

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-002: Pool-directed transfers charge the burn on top of `amount`, causing exact-balance sells and exact-amount integrations to revert

**Confidence:** high | **Locations:** `0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:481, 0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:484, 0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:489, 0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:496, 0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:545`

On transfers to `uniswapPoolAddress`, `_transfer` first removes the full `amount` from the sender and credits the recipient with that full `amount`, then separately calls `_burn(from, burnAmount)`. The sender therefore needs enough balance for `amount + burnAmount`, not just `amount`.

**Impact:** Users cannot exit with their full displayed balance to the configured pool, and protocols that attempt exact-amount sells, repayments, liquidations, or withdrawals to that address can revert unexpectedly. This can strand dust permanently and break integrations that assume `amount` is the total debited from the sender.

**Paths:**

- A user with balance `B` calls `transfer(uniswapPoolAddress, B)` or an integration tries to transfer an exact balance to the pool.

- The contract subtracts `B` and credits the pool `B`, leaving the sender with zero.

- `_burn(sender, burnAmount)` then reverts with `ERC20: burn amount exceeds balance` because the burn is charged on top of `amount`.

*Round 1 | Agents: codex_1*

---

### F-004: Owner can retarget the broken sell-path logic to any arbitrary destination address

**Confidence:** medium | **Locations:** `0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:282, 0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:283, 0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:489, 0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:496`

`uniswapPoolAddress` is owner-controlled and is the sole switch for the non-standard transfer path that over-burns senders, breaks exact-balance exits, and emits misleading logs. The owner can therefore redirect this punitive logic from the intended pool to any arbitrary address at any time.

**Impact:** A privileged owner can unexpectedly make transfers to a bridge, vault, exchange deposit address, router, or replacement pool start reverting exact-amount flows or charging extra sender loss. This creates a realistic griefing and integration-breakage vector for any protocol or user that sends tokens to the retargeted address.

**Paths:**

- The owner calls `setUniswapPoolAddress(target)`.

- Users or protocols continue sending tokens to `target` under normal ERC20 assumptions.

- Transfers to `target` now execute the broken sell-path logic, causing extra burns, exact-amount failures, and misleading logs for that destination.

*Round 1 | Agents: codex_1, opencode_1*

---

## Low (1)

### F-003: Sell-path Transfer events do not match actual balance changes

**Confidence:** high | **Locations:** `0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:484, 0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:487, 0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:494, 0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:495, 0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol:553`

For transfers to `uniswapPoolAddress`, storage credits the pool with the full `amount` and never credits `marketingWalletAddress`, yet the contract emits events claiming only 97% reached the pool and 2% was sent to the marketing wallet. The event stream therefore misrepresents the actual token movements.

**Impact:** Indexers, accounting systems, tax tooling, snapshot systems, and exchange processors that rely on `Transfer` logs can record nonexistent marketing transfers and incorrect recipient amounts, causing reconciliation failures and potentially incorrect credits or balances off-chain.

**Paths:**

- A transfer is made to `uniswapPoolAddress`.

- State changes give the pool the full `amount` and burn only the extra `burnAmount` from the sender.

- The emitted logs instead describe a 97% transfer to the pool and a 2% transfer to `marketingWalletAddress`, which never occurred in storage.

*Round 1 | Agents: codex_1*

---
