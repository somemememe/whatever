# Audit Report

**Total findings:** 3

## Critical (1)

### F-001: Unchecked arithmetic in `withdraw()` lets any caller drain staking tokens

**Confidence:** high | **Locations:** `onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:201, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:202, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:258, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:262, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:263, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:265`

`withdraw()` forwards any user-supplied `amount` into `_withdraw()` without checking `amount <= _balances[msg.sender]`. Because the contract is compiled with Solidity 0.7.5, the raw subtractions of `_totalSupply` and `_balances[user]` in `_withdraw()` wrap on underflow instead of reverting, and the function still executes a real `stakingToken.transfer(recipient, amount)` afterward.

**Impact:** Any address, including one with zero recorded stake, can withdraw arbitrary staking tokens up to the contract's actual token balance. This can drain all deposited principal and permanently corrupt staking and reward accounting for remaining users.

**Paths:**

- An attacker calls `withdraw(amount)` with `amount` greater than their recorded balance, even from an address with zero stake.

- `_withdraw()` underflows `_totalSupply` and `_balances[attacker]` because no balance check exists and Solidity 0.7.5 does not auto-revert on arithmetic underflow.

- The contract then transfers `amount` real staking tokens to the attacker.

- The attacker repeats until the contract's staking-token balance is exhausted.

*Round 1 | Agents: codex_1, opencode_1*

---

## High (1)

### F-002: Rewards are scheduled against a farm-local counter, so the shared token mint cap can make accrued rewards permanently unclaimable

**Confidence:** high | **Locations:** `onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:90, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:95, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:115, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:116, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:118, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:283, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/MintableToken.sol:11, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/MintableToken.sol:12, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/MintableToken.sol:46, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/MintableToken.sol:47, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/MintableToken.sol:49, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/OnDemandToken.sol:9, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/OnDemandToken.sol:13, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/OnDemandToken.sol:20, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/OnDemandToken.sol:32, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/OnDemandToken.sol:36, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/OnDemandToken.sol:37`

The farm snapshots `maxAllowedTotalSupply` into `maxEverTotalRewards` and only checks its own cumulative `timeData.totalRewardsSupply + _reward <= maxEverTotalRewards` in `notifyRewardAmount()`. Actual mintability is enforced later by the reward token's global `everMinted` counter inside `MintableToken._assertMaxSupply()`, and `OnDemandToken` allows the owner or any configured minter to consume that shared cap outside this farm. As a result, scheduled rewards are not actually reserved for stakers.

**Impact:** The farm can promise and accrue rewards that later revert in `getReward()` and `exit()` once the reward token's lifetime mint cap has been consumed elsewhere. This creates reward insolvency, makes pending rewards permanently unclaimable after cap exhaustion, and breaks the one-transaction `exit()` flow for affected users, although users can still withdraw principal separately.

**Paths:**

- Some of the reward token's lifetime cap is already consumed before rewards are scheduled, or another authorized minter consumes cap after scheduling.

- `notifyRewardAmount(_reward)` still succeeds because it only compares the farm-local `totalRewardsSupply` against the token's maximum cap, not against remaining global mint headroom.

- Users stake and accrue rewards normally.

- When a user calls `getReward()` or `exit()`, the farm calls `OnDemandToken.mint(recipient, reward)`.

- `MintableToken._assertMaxSupply()` reverts because `everMinted + reward` exceeds `maxAllowedTotalSupply`, so the reward claim cannot complete.

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (1)

### F-003: Stake accounting credits the requested amount instead of the tokens actually received

**Confidence:** low | **Locations:** `onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:242, onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:243, onchain_auto/0xb3fb1d01b01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:249`

`_stake()` increases `_totalSupply` and `_balances[user]` by the caller-supplied `amount` before verifying how many staking tokens were actually received, and it never reconciles the post-transfer balance delta. If the configured staking token is fee-on-transfer, deflationary, rebasing, or otherwise non-standard, the contract can over-credit deposits relative to assets actually held.

**Impact:** An over-credited depositor can later withdraw more value than they truly contributed, diluting or stealing from other stakers, or the pool can become insolvent and start reverting withdrawals once the contract runs short of staking tokens.

**Paths:**

- The protocol configures a staking token whose `transferFrom` delivers less than the nominal `amount`.

- A user calls `stake(amount)` and the contract credits `_totalSupply` and `_balances[user]` for the full `amount`.

- The contract receives fewer than `amount` tokens but keeps the inflated internal accounting.

- Later withdrawals are overpaid relative to assets received, or honest users encounter failed withdrawals because the pool is undercollateralized.

*Round 1 | Agents: codex_1*

---
