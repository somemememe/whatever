# Audit Report

**Total findings:** 7

## Critical (1)

### F-001: MasterChef migrator can replace real LP collateral with worthless tokens and steal all staked funds

**Confidence:** high | **Locations:** `0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:132, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:137, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:142, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/Migrator.sol:28`

`setMigrator()` lets the owner install an arbitrary migrator, and `migrate()` then approves that migrator for the pool's entire LP balance before only checking that the replacement token reports the same `balanceOf(address(this))`. A malicious migrator can pull out the real LP tokens, mint or otherwise return a fake token that reports the same balance, and permanently swap the pool to the worthless replacement.

**Impact:** All LP tokens in a migrated pool can be stolen, while users are left with accounting claims on fake LP tokens when they later withdraw.

**Paths:**

- Owner sets a malicious migrator with `setMigrator()`

- Anyone calls `migrate(pid)`

- MasterChef approves the migrator for the pool's full LP balance

- Migrator transfers out the genuine LP tokens and returns a fake token with a spoofed/minted matching balance

- MasterChef updates `pool.lpToken`, so future withdrawals return the fake asset instead of the original collateral

*Round 1 | Agents: codex_1, opencode_1*

---

## High (2)

### F-002: SUSHI governance votes are not updated on transfers, enabling double-counted voting power

**Confidence:** high | **Locations:** `0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiToken.sol:12, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiToken.sol:184, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/@openzeppelin/contracts/token/ERC20/ERC20.sol:115, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/@openzeppelin/contracts/token/ERC20/ERC20.sol:152, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/@openzeppelin/contracts/token/ERC20/ERC20.sol:208`

`SushiToken` updates delegate checkpoints on mint and explicit delegation, but it never overrides ERC20 transfer logic to call `_moveDelegates` when balances move between users. A holder can delegate, transfer tokens away, and retain the old voting power while the recipient can also delegate the received tokens.

**Impact:** Governance power can be inflated above token supply, allowing proposals or votes to succeed with phantom voting power no longer backed by ownership.

**Paths:**

- Alice delegates her SUSHI to herself

- Alice transfers those SUSHI to Bob through the inherited ERC20 transfer path

- No delegate checkpoint movement occurs on transfer, so Alice keeps her recorded votes

- Bob delegates the received SUSHI and obtains an additional full set of votes

*Round 1 | Agents: codex_1*

---

### F-003: First xSUSHI minter can steal all SUSHI sent to SushiBar before staking starts

**Confidence:** high | **Locations:** `0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiBar.sol:23, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiBar.sol:29, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiBar.sol:43, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiMaker.sol:195`

When `totalShares == 0`, `SushiBar.enter()` mints xSUSHI 1:1 against only the caller's deposit and ignores any SUSHI already sitting in the bar. If SUSHI is transferred into the bar before the first legitimate staker arrives, the first depositor can mint a trivial number of shares and redeem them for the entire prefunded balance.

**Impact:** Any bootstrap balance, donations, or early fee conversions sent to `SushiBar` before the first deposit can be fully captured by a dust-sized first deposit.

**Paths:**

- SUSHI is transferred into `SushiBar` before any xSUSHI exists

- Attacker calls `enter()` with a minimal amount and receives the same number of shares

- Because total share supply was zero, the prefunded SUSHI was not reflected in mint pricing

- Attacker immediately calls `leave()` and withdraws essentially the full bar balance

*Round 1 | Agents: codex_1*

---

## Medium (3)

### F-005: Stale `pendingOwner` survives direct ownership transfer and can later seize SushiMaker

**Confidence:** high | **Locations:** `0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/BoringOwnable.sol:30, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/BoringOwnable.sol:36, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/BoringOwnable.sol:46, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiMaker.sol:17`

`BoringOwnable.transferOwnership(..., direct = true, ...)` updates `owner` but never clears an existing `pendingOwner`. If ownership is first offered to one address and later directly transferred to another, the stale pending owner can still call `claimOwnership()` and overwrite the newer owner.

**Impact:** A previously nominated address can unexpectedly retake control of `SushiMaker` and then change bridges or otherwise redirect or sabotage fee conversions.

**Paths:**

- Current owner calls `transferOwnership(alice, false, false)`

- Before Alice claims, the owner directly transfers ownership to Bob with `transferOwnership(bob, true, false)`

- `pendingOwner` remains Alice

- Alice later calls `claimOwnership()` and becomes owner, displacing Bob

*Round 1 | Agents: codex_1*

---

### F-006: Reentrant pool tokens can double-claim rewards because MasterChef updates debt after external token transfer

**Confidence:** medium | **Locations:** `0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:203, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:206, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:210, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:214, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:217`

In `deposit()`, MasterChef pays pending SUSHI and then performs an external `lpToken.safeTransferFrom(...)` before updating `user.rewardDebt`. If a listed pool token is malicious or hook-enabled, its `transferFrom` can reenter MasterChef and call `deposit(pid, 0)` while the caller still has the old `rewardDebt`, allowing the same pending reward to be claimed again.

**Impact:** A malicious listed pool token can drain SUSHI rewards allocated to its pool and potentially deplete the MasterChef reward balance faster than intended.

**Paths:**

- Attacker stakes in a pool whose LP token can execute callbacks during `transferFrom`

- Attacker accumulates pending SUSHI rewards

- Attacker calls `deposit(pid, amount)`

- MasterChef sends the pending reward, then calls the LP token's `transferFrom` before updating `rewardDebt`

- The token reenters `deposit(pid, 0)` and the old debt allows the same pending reward to be paid again

*Round 1 | Agents: codex_1*

---

### F-007: MasterChef over-credits fee-on-transfer tokens, creating withdrawal insolvency and cross-user loss

**Confidence:** medium | **Locations:** `0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:166, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:189, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:214, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:215, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:232, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/MasterChef.sol:233`

`deposit()` credits `user.amount += _amount` based on the requested transfer amount instead of the amount actually received by MasterChef. If a listed LP token charges transfer fees or burns on transfer, user balances become overstated relative to the contract's real token balance, while reward accounting elsewhere uses the actual `balanceOf(address(this))`.

**Impact:** Pools that use deflationary or taxed tokens can become insolvent: some users will be unable to withdraw their recorded balances, or later withdrawals will be paid out using tokens that should have backed other users.

**Paths:**

- A fee-on-transfer token is added as a pool token

- User deposits 100 tokens but MasterChef receives fewer than 100

- MasterChef still records the user as owning the full 100 deposit amount

- As more such deposits occur, recorded liabilities exceed actual token holdings

- Later withdrawals either revert for insufficient balance or shift the shortfall onto other users

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-004: Transient xSUSHI holders can capture SushiMaker fee conversions meant for long-term stakers

**Confidence:** medium | **Locations:** `0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiMaker.sol:81, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiMaker.sol:85, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiMaker.sol:195, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiBar.sol:23, 0xe11fc0b43ab98eb91e9836129d1ee7c3bc95df50/contracts/SushiBar.sol:43`

SushiMaker sends converted SUSHI directly to `SushiBar` at conversion time, while xSUSHI ownership is purely balance-based with no holding-period or snapshot requirement. A trader can temporarily acquire a dominant share of xSUSHI just before calling `convert()`, then exit immediately after the conversion and take most of the new rewards despite only holding the shares briefly.

**Impact:** Pending fee revenue can be siphoned from long-term xSUSHI holders by short-term capital, reducing the value accrual that the bar is supposed to deliver to persistent stakers.

**Paths:**

- Attacker deposits enough SUSHI into `SushiBar` to control most xSUSHI outstanding

- Attacker calls `SushiMaker.convert(...)` while holding that temporary stake

- Converted SUSHI is transferred straight into `SushiBar`

- Attacker burns the temporary xSUSHI position and withdraws most of the just-converted rewards

*Round 1 | Agents: codex_1*

---
