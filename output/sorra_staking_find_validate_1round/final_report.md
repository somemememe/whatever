# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: Matured rewards can be claimed repeatedly by splitting withdrawals

**Confidence:** high | **Locations:** `onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:118, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:120, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:213, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:233`

`withdraw()` always computes `rewardAmount = getPendingRewards(msg.sender)` across every matured deposit before reducing principal, but the contract never records that rewards for a deposit were already paid. A user can therefore withdraw only a small slice of matured principal, receive the full matured reward for the entire position, keep most principal staked, and repeat until the pool is drained.

**Impact:** A staker can extract the same matured reward many times and drain tokens owed to other users. For example, a fully vested 100-token deposit in the 40% tier can be withdrawn 1 token at a time and collect roughly the 40-token reward on each call until contract liquidity is exhausted.

**Paths:**

- Deposit into any tier and wait until the lock period expires

- Call `withdraw()` for a small amount of matured principal

- Receive that principal plus the full reward for all matured deposits

- Repeat partial withdrawals because no per-deposit reward-claimed state is ever updated

*Round 1 | Agents: codex*

---

## High (2)

### F-002: Rewards are paid from the same token pool that backs user principal, so fixed reward promises can make the pool insolvent

**Confidence:** high | **Locations:** `onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:53, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:95, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:98, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:100, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:118, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:125, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:167, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:210, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:233`

The contract accepts deposits and pays both principal and rewards in the same `rewardToken`, but it only tracks and caps principal through `totalDeposits` and `MAX_POOL_CAP`. It never reserves, escrows, or checks funding for accrued rewards, so withdrawal payouts come directly from the shared token balance, which includes later users' principal.

**Impact:** Even without exploiting another bug, normal rewarded withdrawals can make the pool insolvent and strand honest users' principal. At the 40% tier, a pool filled to the 10,000,000-token cap can owe 14,000,000 tokens after maturation while only receiving 10,000,000 from stakers unless the owner injects the shortfall off-chain.

**Paths:**

- Users deposit until the pool is near `MAX_POOL_CAP`

- Rewards accrue via `_calculateRewards()` but no on-chain reserve is created

- Earlier matured users withdraw principal plus rewards from the contract's only token balance

- Remaining assets can fall below outstanding principal owed to later users, causing their withdrawals to fail

*Round 1 | Agents: codex*

---

### F-004: Owner emergency withdrawal can seize all staked funds

**Confidence:** medium | **Locations:** `onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:246, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:249, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:251`

`emergencyWithdraw()` lets the owner transfer any amount of the staking token to themselves, and passing `_amount == 0` withdraws the entire token balance. The function does not exclude user principal, does not preserve funds needed for pending withdrawals, and does not update `positions` or `totalDeposits` after removing assets.

**Impact:** A malicious or compromised owner can drain all deposited tokens and permanently break user withdrawals while on-chain accounting still shows users as fully funded.

**Paths:**

- Users deposit tokens into the pool

- Owner calls `emergencyWithdraw(0)` or withdraws most of the balance

- The contract transfers user-backed assets to the owner without adjusting liabilities

- Users remain recorded as stakers but later withdrawals fail because the assets are gone

*Round 1 | Agents: codex*

---

## Medium (1)

### F-003: Fee-on-transfer or deflationary tokens make internal balances exceed real assets

**Confidence:** medium | **Locations:** `onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:67, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:100, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:101, onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:167`

`deposit()` credits `_amount` to the user position and `totalDeposits` immediately after `safeTransferFrom`, but it never measures how many tokens were actually received. If the configured token burns fees, taxes transfers, or otherwise delivers less than requested, the contract records more principal than it owns from the first deposit onward.

**Impact:** The pool becomes insolvent and can revert on later withdrawals because it owes more tokens than it actually holds. Pool-cap and position accounting are also overstated, compounding the mismatch.

**Paths:**

- Deploy the staking pool with a fee-on-transfer or deflationary ERC20

- A user deposits 100 tokens but the contract receives less than 100

- The contract still records a 100-token deposit and increments `totalDeposits` by 100

- Later withdrawals attempt to transfer more tokens than the contract balance contains

*Round 1 | Agents: codex*

---
