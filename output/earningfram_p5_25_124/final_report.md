# Audit Report

**Total findings:** 5

## High (2)

### F-001: Small withdrawals can redeem assets while burning zero shares

**Confidence:** high | **Locations:** `0x863e572b215fd67c855d973f870266cf827aea5e/contracts/core/Vault.sol:127, 0x863e572b215fd67c855d973f870266cf827aea5e/contracts/core/Vault.sol:132, 0x863e572b215fd67c855d973f870266cf827aea5e/contracts/core/Vault.sol:142`

`withdraw()` first checks the caller's entitlement in asset terms via `convertToAssets(balanceOf(msg.sender))`, but then computes `shares = (totalSupply() * assets) / totalAssets()` with floor rounding and never requires `shares > 0`. Whenever `totalAssets() > totalSupply()`, sufficiently small `assets` values can pass the entitlement check while rounding the burned share amount down to zero.

**Impact:** A shareholder can repeatedly withdraw small amounts of underlying without reducing their share balance, draining accrued yield or other surplus from the vault and stealing value from honest LPs.

**Paths:**

- Vault accrues yield so that `totalAssets() > totalSupply()`.

- Attacker acquires any positive share balance.

- Attacker repeatedly calls `withdraw()` with small `assets` values such that `convertToAssets(balanceOf(attacker)) >= assets` but `(totalSupply() * assets) / totalAssets() == 0`.

*Round 1 | Agents: codex_1*

---

### F-002: Configured sub-strategy can arbitrarily mint unbacked shares and drain vault assets

**Confidence:** medium | **Locations:** `0x863e572b215fd67c855d973f870266cf827aea5e/contracts/core/Vault.sol:118, 0x863e572b215fd67c855d973f870266cf827aea5e/contracts/core/Vault.sol:188`

The `subStrategy` address is authorized to call `mint()` and mint any amount of vault shares to any account, with no requirement that assets were deposited or accounting was updated first. Those newly minted shares participate fully in `withdraw()`.

**Impact:** If the configured sub-strategy is malicious, compromised, or unexpectedly upgradeable, it can mint itself overwhelming voting/economic ownership and redeem most or all controller-held assets, diluting honest depositors to near zero.

**Paths:**

- Owner configures a sub-strategy address.

- That address is compromised or malicious and calls `mint(veryLargeAmount, attacker)`.

- Attacker redeems the unbacked shares through `withdraw()` to pull out underlying assets.

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-003: Deposit share pricing can under-mint users by valuing the vault after their ETH is transferred

**Confidence:** medium | **Locations:** `0x863e572b215fd67c855d973f870266cf827aea5e/contracts/core/Vault.sol:97, 0x863e572b215fd67c855d973f870266cf827aea5e/contracts/core/Vault.sol:101, 0x863e572b215fd67c855d973f870266cf827aea5e/contracts/core/Vault.sol:110`

`deposit()` transfers the user's ETH to the controller before reading `IController(controller).totalAssets()`, then uses that post-transfer value as the denominator for share minting. If `totalAssets()` counts the controller's current ETH balance, the depositor's own funds are included in the 'pre-deposit' TVL snapshot and the minted shares are rounded down against an inflated denominator.

**Impact:** New depositors can receive fewer shares than their contribution should buy, creating systematic value transfer from incoming users to existing shareholders.

**Paths:**

- Vault already has existing shares and assets.

- Victim calls `deposit()`.

- Vault forwards ETH to `controller` before fetching `totalAssets()`.

- `totalAssets()` includes the just-transferred ETH, so the share formula uses an inflated denominator and mints too few shares.

*Round 1 | Agents: codex_1*

---

### F-004: Deposits can succeed while minting zero shares

**Confidence:** high | **Locations:** `0x863e572b215fd67c855d973f870266cf827aea5e/contracts/core/Vault.sol:105, 0x863e572b215fd67c855d973f870266cf827aea5e/contracts/core/Vault.sol:110, 0x863e572b215fd67c855d973f870266cf827aea5e/contracts/core/Vault.sol:113`

`deposit()` only requires `newDeposit > 0` and never checks that the computed `shares` is non-zero. When price per share rises above 1, sufficiently small deposits will round down to zero shares and still be accepted.

**Impact:** Small depositors can irreversibly donate assets to the vault without receiving any shares, causing direct fund loss and enriching existing LPs.

**Paths:**

- Vault share price rises above 1 because `totalAssets() > totalSupply()`.

- A user makes a small deposit.

- `shares = (totalSupply() * newDeposit) / totalDeposit` rounds down to 0, but `_mint(receiver, 0)` still succeeds and the assets remain in the system.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-005: Excess ETH sent to deposit is silently accepted and not credited

**Confidence:** high | **Locations:** `0x863e572b215fd67c855d973f870266cf827aea5e/contracts/core/Vault.sol:93, 0x863e572b215fd67c855d973f870266cf827aea5e/contracts/core/Vault.sol:97`

`deposit()` only checks `msg.value >= assets` and forwards exactly `assets` ETH to the controller. Any excess ETH sent with the call is neither refunded nor included in the share calculation.

**Impact:** Users who overpay lose the surplus ETH. That value becomes an uncredited donation sitting in the vault and can later be socialized to share holders instead of the sender.

**Paths:**

- User calls `deposit(assets, receiver)` with `msg.value > assets`.

- Vault transfers only `assets` to the controller and mints shares based only on `assets`.

- The surplus ETH remains uncredited in the vault, with no refund path for the sender.

*Round 1 | Agents: merge_review*

---
