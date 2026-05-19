# Audit Report

**Total findings:** 3

## Critical (1)

### F-001: Unbounded `stakeWeek` lets a staker mint an arbitrarily large bonus and drain the pool

**Confidence:** high | **Locations:** `0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:45, 0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:59, 0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:76, 0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:91, 0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:92, 0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:140, 0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:146`

`stake()` accepts any positive `stakeWeek`, and both `harvest()` and `unstake()` pay a bonus of `pending * (stakingWeek - 1) * 9 / 100`. Because there is no upper bound or normalization on `stakingWeek`, an attacker can choose an extreme value and turn even a small amount of accrued base reward into an arbitrarily large claim on the contract's shared token balance.

**Impact:** A permissionless staker can drain not only funded rewards but also other users' deposited principal held by the contract. Once enough balance is extracted, later harvests and unstakes revert, causing theft and permanent lockup for honest users.

**Paths:**

- Attacker calls `stake(tinyAmount, hugeStakeWeek)` while staking is open.

- After any nonzero base reward accrues, the attacker calls `harvest(stakeCount)` or waits to call `unstake(stakeCount)`.

- The computed `bonus` becomes enormous and is transferred from the contract's pooled JUICE balance, depleting rewards and potentially user principal.

*Round 1 | Agents: codex_1*

---

## High (2)

### F-003: Reward emissions are underfunded because `rewardTokens` do not cover bonus liabilities

**Confidence:** high | **Locations:** `0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:76, 0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:92, 0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:140, 0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:146, 0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:160, 0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:165, 0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:171`

`startStaking()` funds only `rewardTokens` and sets `rewardPerSecond` so exactly that base amount is emitted over 90 days. However, every payout is `pending + bonus`, and the bonus component is never prefunded, reserved, or reflected in `rewardPerSecond`. Any stake with `stakingWeek > 1` therefore creates liabilities larger than the funded reward inventory.

**Impact:** Even without abusing an extreme `stakeWeek`, the pool becomes economically insolvent once boosted positions accrue rewards. The contract eventually has to pay bonuses out of other users' principal, and later harvest/unstake calls can revert when the remaining balance is insufficient.

**Paths:**

- Owner starts staking with `rewardTokens`, funding only the base emission schedule.

- Users stake with `stakeWeek > 1`, so each harvest/unstake includes an extra bonus on top of emitted rewards.

- As boosted claims accumulate, the contract balance no longer covers all promised rewards plus principals, and later exits fail.

*Round 1 | Agents: codex_1*

---

### F-004: Owner can rug accrued user rewards through `rescueReward`

**Confidence:** high | **Locations:** `0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:76, 0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:92, 0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:169, 0x8584ddbd1e28bca4bc6fb96bafe39f850301940e/contracts/JuiceStaking.sol:171`

`rescueReward()` lets the owner transfer `balanceOf(this) - JuiceStaked`, treating only principal as reserved. It ignores already-accrued but unharvested base rewards and all outstanding bonus liabilities, so the owner can withdraw tokens that are economically owed to active stakers.

**Impact:** The owner can strip the reward inventory at any time, causing users to lose accrued rewards. Because `unstake()` transfers principal and rewards together in one call, removing reward liquidity can also make matured positions impossible to exit, creating a de facto rug and lockup.

**Paths:**

- Users stake and accrue pending rewards.

- Before they harvest or unstake, the owner calls `rescueReward(receiver)` and withdraws all balance not counted as `JuiceStaked`.

- Subsequent `harvest()` or `unstake()` calls revert once the contract no longer has enough tokens to satisfy `pending + bonus` or `amount + pending + bonus`.

*Round 1 | Agents: codex_1*

---
