# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: Anyone can mint vault shares using assets already sitting in the vault

**Confidence:** high | **Locations:** `onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:87, onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:98, onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:101, onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:114`

`deposit` never pulls assets from `msg.sender`. It only checks that the vault already holds at least `assets`, forwards those pre-existing funds to the controller, and then mints shares to an arbitrary `receiver`.

**Impact:** A caller can steal credit for someone else's prefunded deposit or claim any tokens/ETH accidentally sent to the vault, receiving newly minted shares without contributing assets.

**Paths:**

- A victim transfers underlying tokens or ETH to the vault address before calling `deposit`, because the vault has no `transferFrom` step.

- An attacker sees the prefunded balance and calls `deposit(victimAmount, attacker)` first.

- The vault forwards the victim-funded assets to the controller and mints the corresponding vault shares to the attacker.

*Round 1 | Agents: codex_1*

---

## High (1)

### F-002: Rounding down in `withdraw` lets users withdraw assets while burning zero shares

**Confidence:** high | **Locations:** `onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:125, onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:137, onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:139, onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:170, onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:174`

`withdraw` computes `shares = (totalSupply() * assets) / totalAssets(false)` with floor division and never requires `shares > 0`. When assets-per-share exceeds 1, sufficiently small withdrawals burn zero shares but still execute `controller.withdraw`.

**Impact:** Any caller that can access `withdraw` can steal accrued yield or any other surplus above principal without owning shares, draining the vault back down toward a 1:1 asset/share ratio.

**Paths:**

- Yield accrues so `IController(controller).totalAssets(false) > totalSupply()`.

- The attacker calls `withdraw(assets, attacker)` with `assets < totalAssets / totalSupply`, making the computed `shares` equal to 0.

- `balanceOf(msg.sender) >= 0` passes, `_burn(msg.sender, 0)` does nothing, and the controller still transfers real assets to the attacker.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-003: Small deposits can transfer assets into the strategy while minting zero shares

**Confidence:** high | **Locations:** `onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:101, onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:104, onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:106, onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:111, onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:114`

Deposits mint `shares = (totalSupply() * newDeposit) / totalDeposit` using floor division and do not require `shares > 0`. A positive deposit can therefore be forwarded into the controller while minting zero vault shares.

**Impact:** Small depositors can permanently lose assets to incumbent shareholders once the share price rises enough that their deposit rounds down to zero shares.

**Paths:**

- The vault's assets per share rises above 1 after yield or donations.

- A user deposits a small amount such that `(totalSupply() * newDeposit) / totalDeposit == 0`.

- The vault transfers the assets into the controller, but `_mint(receiver, 0)` leaves the depositor with no claim on them.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-004: Whitelist enforcement is bypassed for every direct EOA caller

**Confidence:** high | **Locations:** `onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:64, onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:65, onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:92, onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:130, onchain_auto/0x80cb73074a6965f60df59bf8fa3ce398ffa2702c/contracts/core/Vault.sol:150`

The `onlyAllowed` modifier permits any call where `tx.origin == msg.sender`, so the whitelist is only enforced for contract callers. Any direct EOA bypasses `IWhitelist(whiteList).listed(msg.sender)` entirely.

**Impact:** The vault cannot rely on its whitelist/KYC gate to restrict direct users: any EOA can call `deposit`, `withdraw`, and `redeem` even if unlisted.

**Paths:**

- An unlisted EOA calls `deposit`, `withdraw`, or `redeem` directly.

- Because the call originates from an EOA, `tx.origin == msg.sender` is true.

- `onlyAllowed` succeeds without consulting the whitelist.

*Round 1 | Agents: codex_1*

---
