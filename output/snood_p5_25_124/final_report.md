# Audit Report

**Total findings:** 5

## Critical (1)

### F-001: Bridge owner can mint arbitrary unbacked tokens without consuming any burn record

**Confidence:** high | **Locations:** `onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:94, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:104, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:106, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:108, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:109`

`sendTokens` only burns tokens and increments an informational `_tokensSent` counter, while `receiveTokens` only checks that the caller is `_bridgeOwner` and that `_feesPaid[account][networkId] >= fee`. It never verifies that `amount` matches any prior burn, never consumes a burn record, and even allows `fee = 0`, so `_bridgeOwner` can mint any amount to any account at will.

**Impact:** A malicious or compromised bridge owner can inflate supply arbitrarily, mint unbacked tokens to itself or collaborators, dump them, and destroy the token's value. Honest users who burn for bridging also have no on-chain guarantee that the destination mint matches what was burned.

**Paths:**

- User burns through `sendTokens(networkId, amount)`; only `_tokensSent` is incremented and no claim record is locked or consumed.

- `_bridgeOwner` calls `receiveTokens(attacker, anyNetworkId, hugeAmount, 0)`.

- The contract mints `hugeAmount` to the attacker without proving or matching any prior burn.

*Round 1 | Agents: codex_1, opencode_1*

---

## High (3)

### F-002: Ownership transfer or renounce leaves the previous owner with live `DEFAULT_ADMIN_ROLE` powers

**Confidence:** high | **Locations:** `onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:23, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:25, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/@schnoodle/contracts-upgradeable/access/OwnableUpgradeable.sol:67, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/@schnoodle/contracts-upgradeable/access/OwnableUpgradeable.sol:76, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/@schnoodle/contracts-upgradeable/access/AccessControlUpgradeable.sol:148, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/@schnoodle/contracts-upgradeable/access/AccessControlUpgradeable.sol:161, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/@schnoodle/contracts-upgradeable/access/AccessControlUpgradeable.sol:179`

During `configure(true, ...)`, the current owner is granted `DEFAULT_ADMIN_ROLE` once via `_setupRole(DEFAULT_ADMIN_ROLE, owner())`. Later `transferOwnership` and `renounceOwnership` only update the Ownable owner slot; they never revoke the old admin role or automatically grant it to the new owner. The former owner therefore retains AccessControl admin powers after ownership handoff or renunciation.

**Impact:** A prior owner can continue granting itself privileged roles after the protocol appears transferred or renounced, then freeze users with `LOCKED`, re-authorize farming contracts, or drain the farming reserve via `farmingReward`. This defeats the expected security boundary of ownership transfer.

**Paths:**

- Original owner runs `configure(true, ...)`, gaining `DEFAULT_ADMIN_ROLE`.

- Ownership is transferred or renounced through `transferOwnership`/`renounceOwnership`.

- The former owner still calls `grantRole(FARMING_CONTRACT, formerOwner)` or `grantRole(LOCKED, victim)` and exercises privileged control.

*Round 1 | Agents: codex_1*

---

### F-003: Transfers and burns depend on a mutable external farming contract and can be globally frozen

**Confidence:** high | **Locations:** `onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:39, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:44, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:94, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:145, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:147, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:148`

Every non-mint transfer and burn flows through `_beforeTokenTransfer`, which calls `lockedBalanceOf(from)`. That helper performs a raw external `.call` to `_schnoodleFarming.lockedBalanceOf(account)` and then `assert(success)`. If the farming contract reverts, is misconfigured, is upgraded incompatibly, returns malformed data, or is otherwise unavailable, ordinary transfers and burns revert.

**Impact:** A failure or malicious upgrade of the external farming contract can freeze token mobility across the entire system, including sells and `sendTokens` bridge burns. This creates a single external liveness dependency for core token functionality.

**Paths:**

- A holder transfers or burns tokens.

- `_beforeTokenTransfer` calls `_schnoodleFarming.call(...)` inside `lockedBalanceOf`.

- The external call fails or returns bad data, causing `assert(success)` or `abi.decode` to revert and blocking the token operation.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-004: Hardcoded maintenance routine confiscates balances from listed holder addresses

**Confidence:** high | **Locations:** `onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:127, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:128, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:137, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:139, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:140`

`maintenance()` is an owner-only routine that iterates over a hardcoded list of third-party addresses, revokes their `LOCKED` role, and forcibly `_send`s each address's entire balance to a hardcoded treasury address. The affected holders do not approve or authorize the transfer.

**Impact:** For any address on the list, the owner can unilaterally seize all tokens held there. This is direct custodial confiscation risk for those wallets and demonstrates that listed balances are not protected by holder consent.

**Paths:**

- Owner calls `maintenance()`.

- The function calls `_maintenance(victim)` for each listed address.

- `_maintenance` transfers the victim's full balance to the treasury address.

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (1)

### F-005: `configure(true, ...)` is repeatable and leaves stale farming contracts permanently privileged while stranding the old farming reserve

**Confidence:** medium | **Locations:** `onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:23, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:27, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:28, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:29, onchain_auto/0xeac2a259f3ebb8fd1097aeccaa62e73b6e43d5bf/contracts/SchnoodleV9.sol:76`

`configure(bool initialSetup, ...)` has no one-time guard, so the owner can call it again with `initialSetup = true`. Each such call assigns a fresh `_farmingFund` address and grants `FARMING_CONTRACT` to the new farming contract via `_setupRole`, but it never revokes the prior farming contract's role and never provides any path to recover tokens left in the old `_farmingFund`.

**Impact:** A farming migration or mistaken reconfiguration can permanently strand the existing farming reserve and simultaneously leave retired farming contracts with live authority to call `farmingReward` against the new reserve. This can cause reward insolvency and stale privileged integrations.

**Paths:**

- Owner initially configures farming and fees accumulate into the current `_farmingFund`.

- Owner later calls `configure(true, ..., newFarming, ...)` for a migration or reconfiguration.

- The pointer moves to a new `_farmingFund`, the old reserve becomes unreachable, and the previous farming contract still retains `FARMING_CONTRACT` privileges unless explicitly revoked.

*Round 1 | Agents: merge_review*

---
