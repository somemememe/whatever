# Audit Report

**Total findings:** 6

## Critical (2)

### F-001: Anyone can grant themselves unlimited allowance over tokens held by the contract

**Confidence:** high | **Locations:** `0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:149, 0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:152, 0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:153`

`tokenAllowAll` is publicly callable and has no access control, so any account can set `uint256(-1)` allowance from the contract to an arbitrary `allowee` for any ERC20 `asset`. Because the staking pool holds USDT, an attacker can approve themselves and then drain the contract with `transferFrom`.

**Impact:** Any external user can steal all USDT held by the staking contract, including deposited principal and any prefunded rewards. Any other ERC20 sent to the contract is also drainable.

**Paths:**

- Attacker calls `tokenAllowAll(USDT, attacker)`.

- The contract grants the attacker unlimited USDT allowance.

- Attacker calls `USDT.transferFrom(address(contract), attacker, USDT.balanceOf(address(contract)))` to drain the pool.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-004: Owner can drain all staked USDT at any time

**Confidence:** medium | **Locations:** `0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:134, 0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:137`

`transferAllFunds` lets the owner transfer the contract's entire USDT balance to `_owner` with no liability check, timelock, or user-protection mechanism. The function can empty both user principal and any prefunded rewards in one transaction.

**Impact:** A malicious or compromised owner can steal all funds held by the staking contract, after which user withdrawals and interest claims will fail.

**Paths:**

- Users deposit USDT into the staking contract.

- Owner calls `transferAllFunds()`.

- The contract transfers its full USDT balance to `_owner`.

- Users can no longer recover principal or rewards from the emptied pool.

*Round 1 | Agents: codex_1, opencode_1*

---

## High (3)

### F-002: Interest is paid from pooled deposits with no enforced reward backing, making the pool structurally insolvent

**Confidence:** high | **Locations:** `0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:99, 0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:145, 0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:172`

The contract only acquires funds from user deposits, but `claimInterestForDeposit` transfers additional USDT as yield from the same shared token balance. There is no segregated reward reserve, solvency check, or liability accounting ensuring principal plus promised rewards remain fully backed.

**Impact:** Early claimants are paid out of later users' deposits unless the owner manually tops up the contract off-path. Once cumulative interest payouts exceed any excess prefunding, later withdrawals and claims can fail due to insufficient USDT, leaving users with unrecoverable principal or rewards.

**Paths:**

- Users deposit USDT through `deposit()`.

- Some users call `claimInterestForDeposit()` and receive extra USDT from the contract balance.

- The remaining pool balance falls below outstanding principal plus accrued rewards.

- Later user withdrawals or claims revert because the contract no longer holds enough USDT.

*Round 1 | Agents: codex_1*

---

### F-003: Deposits continue accruing rewards indefinitely after maturity

**Confidence:** high | **Locations:** `0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:122, 0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:144, 0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:145, 0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:157, 0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:167`

`calculateInterest` uses `block.timestamp - lastClaimTime` without capping accrual at `depositTime + lockupPeriod`, and `claimInterestForDeposit` allows claiming at any time. A user can therefore leave principal in the contract after the advertised 7/14/30/60/90-day term and keep harvesting rewards forever.

**Impact:** A depositor can extract rewards far beyond the stated lockup program, accelerating depletion of the shared USDT balance and worsening insolvency for all other users.

**Paths:**

- User makes a deposit in any tier.

- The lockup period expires, but the user does not withdraw principal.

- The user repeatedly calls `claimInterestForDeposit(lockupPeriod)` over time.

- Rewards keep accruing after maturity because accrual is never capped.

*Round 1 | Agents: codex_1*

---

### F-005: Owner can arbitrarily freeze user principal and rewards via blacklist

**Confidence:** medium | **Locations:** `0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:105, 0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:119, 0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:157`

The owner can blacklist any address at will, and blacklisted users are hard-blocked from both `withdraw` and `claimInterestForDeposit`. There is no time limit, appeal path, or mechanism preserving the user's ability to recover funds while blacklisted.

**Impact:** A malicious or compromised owner can selectively lock users out of their principal and accrued rewards indefinitely, creating an arbitrary confiscation or coercive freeze risk.

**Paths:**

- Victim deposits USDT through `deposit()`.

- Owner calls `blacklist(victim)`.

- Victim's later `withdraw()` and `claimInterestForDeposit()` calls revert until the owner voluntarily unblacklists them.

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (1)

### F-006: Withdrawing one deposit can permanently brick reward claims for other deposits in the same tier

**Confidence:** high | **Locations:** `0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:127, 0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:143, 0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:157, 0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:163, 0x800cfd4a2ba8ce93ea2cc814fce26c3635169017/Contract.sol[BUSD staking.sol]:165`

`withdraw` zeroes a deposit's `amount` but leaves the record in `_deposits`. Later, `claimInterestForDeposit` iterates every deposit sharing the requested lockup tier and unconditionally `require`s each matching deposit to have `interestToClaim > 0`. For a withdrawn same-tier deposit, `calculateInterest` always returns 0, so the function reverts before paying interest on the user's other same-tier deposits.

**Impact:** After a user withdraws any deposit in a given lockup tier, accrued rewards on the user's remaining deposits in that same tier can become permanently unclaimable, causing loss of yield and a user-specific denial of service.

**Paths:**

- User opens at least two deposits with the same lockup period.

- User later withdraws one of those deposits, which sets that record's `amount` to 0 but keeps it in the array.

- User calls `claimInterestForDeposit(lockupPeriod)` to claim rewards on another active same-tier deposit.

- The loop reaches the withdrawn record, `calculateInterest` returns 0, and `require(interestToClaim > 0)` reverts the entire claim.

*Round 1 | Agents: merge_review*

---
