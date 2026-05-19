# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: Unrestricted fixed reward can be sybil-drained with dust deposits

**Confidence:** high | **Locations:** `0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:48, 0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:49, 0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:50`

Whenever `AaveBoost` holds at least `REWARD` AAVE, `proxyDeposit` always adds a full `REWARD` subsidy to the deposit while charging the caller only `amount`. Because there is no minimum deposit size, per-user quota, cooldown, or access control, any account can repeatedly submit dust-sized deposits for itself and capture nearly the entire subsidy reserve.

**Impact:** An attacker can convert the contract's full reward inventory into attacker-owned pool deposits at negligible cost, stealing all incentives intended for real users.

**Paths:**

- Fund `AaveBoost` with reward AAVE

- Attacker calls `proxyDeposit(aave, attacker, 1)` repeatedly

- Each call transfers only the dust `amount` from the attacker but deposits `amount + REWARD` for the attacker

- Attacker later withdraws the boosted pool position, repeating until the contract balance drops below `REWARD`

*Round 1 | Agents: codex*

---

## High (1)

### F-002: Broken fallback lets anyone sweep the remaining AAVE once rewards are nearly exhausted

**Confidence:** high | **Locations:** `0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:48, 0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:52, 0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:53`

The `else` branch is labeled as a normal deposit fallback, but it never pulls tokens from the caller. Instead it directly calls `pool.deposit(asset, recipient, amount, false)`. For `asset == aave`, the pool can therefore use the standing allowance from `AaveBoost` and pull the remaining contract balance, crediting the recipient even though the caller supplied nothing.

**Impact:** After the reserve falls below `REWARD`, any remaining AAVE can be stolen outright by the next caller, guaranteeing loss of the final tranche of protocol funds.

**Paths:**

- The reward reserve is reduced until `aave.balanceOf(address(this)) < REWARD`

- Attacker calls `proxyDeposit(aave, attacker, remainingBalance)`

- The `else` branch skips `safeTransferFrom(msg.sender, ...)` entirely

- `pool.deposit` pulls the remaining AAVE from `AaveBoost` via its allowance and credits the attacker

*Round 1 | Agents: codex*

---

## Medium (2)

### F-003: Pool migrations leave old pools with permanent unlimited AAVE allowance

**Confidence:** high | **Locations:** `0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:28, 0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:29, 0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:34, 0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:37, 0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:38`

Both the constructor and `setPool` grant the selected pool an effectively unlimited AAVE allowance with `safeIncreaseAllowance`, but `setPool` never revokes the old pool's allowance. Every historical pool address therefore remains approved to spend all current and future AAVE held by `AaveBoost`.

**Impact:** If a deprecated pool is later compromised, upgraded maliciously, or was misconfigured in the first place, it can drain the entire reward reserve even after the protocol has supposedly migrated away from it.

**Paths:**

- The contract is deployed with pool A and later moved to pool B via `setPool`

- Pool A keeps its existing unlimited allowance because nothing resets it to zero

- AAVE reward funds are later sent to `AaveBoost`

- Pool A uses `transferFrom` on the AAVE token to pull those funds out of `AaveBoost`

*Round 1 | Agents: codex*

---

### F-005: `setPool` accepts zero or EOA addresses, which can black-hole user deposits

**Confidence:** high | **Locations:** `0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:22, 0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:34, 0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:35, 0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:49, 0xd2933c86216dc0c938ffafeca3c8a2d6e633e2ca/contracts/AaveBoost.sol:50`

The constructor validates that the initial pool is nonzero, but `setPool` performs no nonzero or code-existence checks. If governance accidentally points `pool` at `address(0)` or an EOA, `proxyDeposit` can still pull AAVE from users in the reward-enabled branch, and the subsequent `pool.deposit(...)` call has no guaranteed target logic to execute.

**Impact:** A bad pool update can turn user deposits into stuck funds inside `AaveBoost` instead of creating pool positions, causing direct user loss rather than a mere outage.

**Paths:**

- Owner calls `setPool` with `address(0)` or an EOA-cast address

- The contract still has enough balance to enter the `if (balance >= REWARD)` branch

- A user calls `proxyDeposit(aave, user, amount)`

- `safeTransferFrom` moves the user's AAVE into `AaveBoost`, but the invalid `pool.deposit` target does not perform the expected deposit

*Round 1 | Agents: codex*

---
