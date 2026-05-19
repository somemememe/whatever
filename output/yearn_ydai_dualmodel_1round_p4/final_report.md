# Audit Report

**Total findings:** 3

## Critical (1)

### F-001: Empty-vault inflation attack can steal later deposits via zero-share minting

**Confidence:** high | **Locations:** `onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:290, onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:326, onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:333, onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:336`

Share issuance uses the pre-deposit ratio `shares = _amount * totalSupply / _pool` without any minimum-share check, while `balance()` includes underlying that reaches the vault outside `deposit()` accounting. An attacker can seed the vault with a dust first deposit, then donate underlying directly so `_pool` becomes very large relative to `totalSupply`, causing later deposits to mint zero or negligible shares.

**Impact:** Victim deposits can be accepted while minting no meaningful yShares, effectively donating their assets to incumbent shareholders. A dust first depositor can then redeem nearly the entire vault balance, including later users' deposits.

**Paths:**

- Attacker makes the first deposit with a dust amount and receives the initial shares 1:1.

- Attacker transfers a large amount of underlying directly to the vault, inflating `balance()` without minting new shares.

- A victim calls `deposit()`; because `_pool` is now huge, `(_amount * totalSupply) / _pool` rounds down to zero or dust.

- The attacker later withdraws their shares and captures almost all underlying, including the victim's deposit.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-002: Permissionless repeated `earn()` calls can drain the withdrawal buffer to dust

**Confidence:** high | **Locations:** `onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:312, onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:316, onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:318`

`available()` returns `token.balanceOf(address(this)) * min / max`, and `earn()` is publicly callable. With the default `min = 9500`, each call transfers 95% of the current on-hand balance to the controller, so repeated calls shrink the intended local withdrawal reserve from 5% to 0.25%, then 0.0125%, and so on.

**Impact:** Any account can permissionlessly force the vault's cash buffer to near zero. After that, even small withdrawals depend on the controller/strategy returning funds immediately; if controller liquidity is impaired, paused, or lossy, users can suffer withdrawal failures, delays, or amplified exit losses.

**Paths:**

- The vault holds idle underlying intended to satisfy cheap small withdrawals.

- An arbitrary caller invokes `earn()` repeatedly.

- Each invocation transfers 95% of the remaining local balance to the controller, leaving only a tiny residue.

- Subsequent withdrawals must rely on `Controller.withdraw(...)`, increasing the risk of permissionless withdrawal DoS or loss amplification when controller liquidity is not immediately available.

*Round 1 | Agents: codex_1, opencode_1*

---

## Low (1)

### F-003: `getPricePerFullShare()` reverts while the vault is empty

**Confidence:** high | **Locations:** `onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:373, onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol:374`

`getPricePerFullShare()` computes `balance() * 1e18 / totalSupply()` without handling the zero-supply case.

**Impact:** Integrations, frontends, and monitors that query price-per-share before the first deposit will revert unexpectedly, which can break initialization and health-check flows.

**Paths:**

- The vault is freshly deployed and `totalSupply()` is zero.

- A caller invokes `getPricePerFullShare()`.

- The division by zero reverts.

*Round 1 | Agents: codex_1, opencode_1*

---
