# Audit Report

**Total findings:** 5

## Critical (1)

### F-001: Vault proxy is deployed uninitialized and can be taken over by the first caller

**Confidence:** high | **Locations:** `0xf0358e8c3cd5fa238a29301d0bea3d63a17bedbe/Contract.sol:183, 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV1.sol:57, 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/inheritance/ControllableInit.sol:12, 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/inheritance/GovernableInit.sol:21`

`VaultProxy` only stores the implementation address in its constructor and does not execute any initializer. The proxied `initializeVault()` entrypoint is public and protected only by OpenZeppelin's one-shot `initializer`, so the first caller to reach a freshly deployed proxy can initialize it with attacker-chosen `_storage` and `_underlying`. Because governance/controller checks are delegated to whatever contract is stored in `_storage`, the attacker can point the vault at a malicious Storage-like contract that recognizes the attacker as governance/controller and then fully control strategy changes and upgrades.

**Impact:** A newly deployed vault proxy can be permanently seized before the intended deployer initializes it. The attacker can then set a malicious strategy, swap storage/governance plumbing, schedule malicious upgrades, and steal or brick all assets that later enter the vault.

**Paths:**

- Deploy `VaultProxy` with a valid implementation address.

- Before the legitimate initialization transaction executes, call `initializeVault(attackerStorage, attackerUnderlying, ...)` through the proxy.

- The proxy becomes permanently initialized with attacker-controlled governance/controller wiring.

- Use the resulting privileged access to install a malicious strategy or upgrade implementation and drain or lock deposited funds.

*Round 1 | Agents: codex_1*

---

## High (3)

### F-002: First depositor can steal assets already sitting in a zero-supply vault

**Confidence:** high | **Locations:** `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV1.sol:153, 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV1.sol:300, 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV1.sol:327`

When `totalSupply() == 0`, `_deposit()` mints shares equal to the new deposit amount and completely ignores any underlying already held by the vault or strategy. If assets exist while share supply is zero, the next depositor can mint shares 1:1 against only their own contribution and then redeem those shares for the entire pre-existing asset base.

**Impact:** Any donated, rescued, residual, or mistakenly transferred underlying that exists while the vault supply is zero can be captured by the next depositor. This creates a direct theft path for assets that are present outside the normal share-accounting flow.

**Paths:**

- The vault reaches `totalSupply == 0` while still holding positive `underlyingBalanceWithInvestment()`.

- An attacker makes a minimal deposit via `deposit`, `depositFor`, or the ERC4626 wrappers.

- Because `_deposit()` uses the zero-supply branch, the attacker receives shares equal only to their deposit instead of being diluted by the pre-existing assets.

- The attacker withdraws their shares and receives the vault's full underlying balance, including assets they did not provide.

*Round 1 | Agents: codex_1*

---

### F-003: ERC4626 `mint()` can charge assets for fewer than the requested shares, including zero shares

**Confidence:** high | **Locations:** `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV2.sol:45, 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV2.sol:49, 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV2.sol:100, 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV1.sol:300`

`mint(_shares)` first computes `assets = convertToAssets(_shares)` using floor division, then forwards those assets into `_deposit()`, which floors again when calculating how many shares to mint. The function never checks that `_deposit()` actually minted `_shares`, so callers can pay assets and receive fewer shares than requested, including zero shares in valid non-empty vault states.

**Impact:** Users and integrators invoking the standard ERC4626 `mint()` path can suffer silent fund loss and broken accounting. In some states the transaction succeeds while transferring assets into the vault and minting zero shares, turning the entire payment into a donation.

**Paths:**

- Assume `totalAssets = 3` and `totalSupply = 2`.

- Call `mint(1, receiver)`. `convertToAssets(1)` returns `floor(1*3/2) = 1` asset.

- `_deposit(1, ...)` then computes minted shares as `floor(1*2/3) = 0`.

- The call succeeds, transfers 1 asset to the vault, and mints 0 shares to the receiver.

*Round 1 | Agents: codex_1*

---

### F-004: ERC4626 `withdraw()` can burn too few shares and return fewer assets than requested

**Confidence:** high | **Locations:** `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV2.sol:59, 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV2.sol:63, 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV2.sol:106, 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV1.sol:327`

`withdraw(_assets, ...)` converts the requested asset amount into shares with `convertToShares(_assets)`, which rounds down. It then burns exactly that rounded-down share count via `_withdraw()`, whose payout math also rounds down, and never verifies that the assets returned equal the requested `_assets`. As a result, `withdraw()` can succeed while returning less underlying than requested.

**Impact:** Exact-asset ERC4626 withdrawals are unreliable. Callers and downstream protocols that assume compliant `withdraw()` semantics can be silently short-paid, leading to direct user loss, accounting errors, and potential downstream undercollateralization.

**Paths:**

- Assume `totalAssets = 5` and `totalSupply = 3`.

- Call `withdraw(2, receiver, owner)`. `convertToShares(2)` returns `floor(2*3/5) = 1` share.

- `_withdraw(1, ...)` pays `floor(5*1/3) = 1` asset.

- The transaction succeeds even though the caller requested 2 assets and only receives 1.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-005: ERC4626 empty-vault helpers revert because `assetsOf()` divides by zero

**Confidence:** high | **Locations:** `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV2.sol:24, 0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV2.sol:55`

`assetsOf()` computes `totalAssets() * balanceOf(_depositor) / totalSupply()` without guarding the zero-supply case, and `maxWithdraw()` calls `assetsOf()` directly. On a fresh or fully emptied vault, these supposedly safe ERC4626 view helpers revert instead of returning 0.

**Impact:** Frontends, wrappers, and automated integrations that rely on standard ERC4626 view functions can break or self-DOS when the vault has zero share supply.

**Paths:**

- Call `assetsOf(user)` when `totalSupply() == 0`.

- Or call `maxWithdraw(user)` when the vault is fresh or fully emptied.

- The call reverts due to division by zero instead of returning 0.

*Round 1 | Agents: codex_1*

---
