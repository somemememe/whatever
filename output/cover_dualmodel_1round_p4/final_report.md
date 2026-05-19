# Audit Report

**Total findings:** 6

## High (3)

### F-001: New deposits can capture COVER rewards accrued before they were staked

**Confidence:** high | **Locations:** `onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:118, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:121, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:125, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:128, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:130`

`deposit()` snapshots `pools[_lpToken]` into memory before calling `updatePool()`, then uses that stale `pool.accRewardsPerToken` both when paying existing rewards and when recomputing the depositor's `rewardWriteoff`. A fresh depositor is therefore not charged for the COVER accrued before their deposit and can later claim a share of historical emissions they did not earn.

**Impact:** An attacker can wait until a pool has accrued substantial unharvested COVER, deposit a very large amount immediately before the next claim, and siphon most of the already-earned COVER rewards away from existing stakers.

**Paths:**

- Let a pool accrue rewards without any interaction so `lastUpdatedAt` is stale

- Deposit a very large amount through `deposit()`

- Because the writeoff is based on the pre-update accumulator, later call `claimRewards()`

- Receive COVER attributable to the period before the attacker was staked

*Round 1 | Agents: codex_1*

---

### F-002: Shared bonus-token accounting lets one pool drain another pool's bonus reserves

**Confidence:** high | **Locations:** `onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:217, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:233, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:266, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:327`

The contract allows the same ERC20 bonus token address to be attached to multiple pools, but both bonus claims and `collectBonusDust()` transfer from the contract's single global balance of that token. There is no per-pool token escrow or accounting isolation.

**Impact:** Users claiming bonuses in one pool can consume reserves intended for another pool, and once any one pool using that token passes its grace period, anyone can sweep the entire shared token balance to treasury and strand bonus programs in the other pools.

**Paths:**

- Governance allows bonus token `X`

- Different programs add bonus token `X` to pool A and pool B

- Claims from pool A or `collectBonusDust(poolA)` spend from Blacksmith's full `X` balance

- Pool B becomes underfunded or completely drained even though its own schedule is still active

*Round 1 | Agents: codex_1*

---

### F-003: SAFE2 migrations can exceed the advertised migration cap

**Confidence:** high | **Locations:** `onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Migrator.sol:27, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Migrator.sol:49, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Migrator.sol:55, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Migrator.sol:63`

`migrationCap` is enforced only inside `claim()`. `migrateSafe2()` mints COVER and increments `safe2Migrated` without checking whether `safe2Migrated + safeClaimed + safe2Balance` would exceed the cap.

**Impact:** If Merkle claims consume most of the cap first, later SAFE2 holders can still migrate and mint additional COVER beyond the intended migration limit, causing excess inflation and diluting all COVER holders.

**Paths:**

- Merkle claimants use `claim()` until `safe2Migrated + safeClaimed` is near `migrationCap`

- A SAFE2 holder then calls `migrateSafe2()`

- The function mints COVER without any cap check

- Total migration issuance ends up above the documented cap

*Round 1 | Agents: codex_1*

---

## Medium (3)

### F-004: Deposits over-credit fee-on-transfer or deflationary LP tokens

**Confidence:** high | **Locations:** `onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:128, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:133, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:153`

`deposit()` increases `miner.amount` by the requested `_amount` before transferring tokens in, and it never reconciles against the amount actually received. If a whitelisted LP token burns, taxes, rebases, or otherwise delivers less than `_amount`, the miner is credited for more stake than the contract actually holds.

**Impact:** A depositor can overstate their stake, over-earn COVER and bonus rewards, and potentially withdraw value that was actually supplied by later users, leaving the pool insolvent once the accounting shortfall is realized.

**Paths:**

- Whitelist or use an LP token with transfer fees or deflationary behavior

- Deposit `X` tokens so the contract receives only `X-Y`

- Receive staking credit for the full `X` anyway

- Claim rewards or withdraw against the inflated balance

*Round 1 | Agents: codex_1, opencode_1*

---

### F-005: Reward-parameter changes apply retroactively to already elapsed time

**Confidence:** high | **Locations:** `onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:169, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:173, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:272, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:291`

`updatePoolWeights()` and `updateWeeklyTotal()` change emission parameters without first checkpointing pools. Later, `_calculateCoverRewardsForPeriod()` applies the current `weeklyTotal`, `pool.weight`, and `totalWeight` to the entire interval since `lastUpdatedAt`, so already elapsed reward time is recalculated using the new settings.

**Impact:** Governance can retroactively redirect rewards that honest users already earned but have not yet been checkpointed, favoring selected pools and depriving others of emissions they expected to receive.

**Paths:**

- Allow one or more pools to sit without `updatePool()` calls

- Change pool weights or `weeklyTotal`

- Trigger an update or harvest afterward

- The elapsed interval is priced using the new parameters rather than the old ones

*Round 1 | Agents: codex_1*

---

### F-006: Team vesting can release arbitrary ERC20s, not just COVER

**Confidence:** high | **Locations:** `onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Vesting.sol:38, onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Vesting.sol:46`

`Vesting.vest()` accepts an arbitrary `IERC20 token` parameter and transfers that token according to the COVER vesting schedule. The contract never binds vesting withdrawals to a specific COVER token address.

**Impact:** Any ERC20 accidentally or intentionally sent to the vesting contract becomes withdrawable by the listed beneficiary wallets up to their vesting entitlements, draining assets that were never meant to be part of the vesting program.

**Paths:**

- Send any ERC20 to the vesting contract

- A team beneficiary calls `vest(arbitraryToken)`

- The contract transfers that arbitrary token out under the COVER vesting schedule

*Round 1 | Agents: codex_1*

---
