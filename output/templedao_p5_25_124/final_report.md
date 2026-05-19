# Audit Report

**Total findings:** 5

## Critical (1)

### F-001: Untrusted migration source lets anyone mint unbacked stake shares and drain the pool

**Confidence:** high | **Locations:** `onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:241, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:242, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:243`

`migrateStake()` trusts a user-supplied `oldStaking` address and an attacker-chosen `amount`. It calls `oldStaking.migrateWithdraw(...)` but never verifies that the caller is migrating from a sanctioned predecessor, that the predecessor uses the same `stakingToken`, or that this contract actually received `amount` tokens before `_applyStake()` credits the balance. A fake contract can therefore return successfully without transferring any staking tokens, while the attacker still receives full staking shares.

**Impact:** An attacker can mint arbitrary unbacked stake balances in the new pool and then redeem them through `withdraw()` for real `stakingToken` held on behalf of honest users, potentially draining the pool.

**Paths:**

- Deploy a fake contract exposing `migrateWithdraw(address,uint256)` that does not transfer any staking tokens

- Call `migrateStake(fakeOldStaking, amount)` on the new `StaxLPStaking` contract

- The fake `migrateWithdraw` returns, and `_applyStake(msg.sender, amount)` credits the attacker with `amount` stake anyway

- Call `withdraw(amount, false)` or `withdrawAll(false)` to extract real staking tokens from the pool

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (2)

### F-002: Stake accounting assumes the contract receives the full requested amount

**Confidence:** low | **Locations:** `onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:121, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:125, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:126, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:129`

`stakeFor()` transfers `_amount` tokens in and then unconditionally credits `_amount` shares via `_applyStake()`. It never measures the actual balance delta. If the configured staking token is fee-on-transfer, deflationary, or otherwise delivers fewer tokens than requested, the contract becomes undercollateralized while the user still receives full stake credit.

**Impact:** A depositor can withdraw more staking tokens than the contract actually received for their position, pushing the shortfall onto other stakers and eventually causing withdrawals to fail once the pool balance is exhausted.

**Paths:**

- Use a staking token that taxes, burns, or otherwise transfers less than the requested `_amount`

- Call `stakeFor(..., amount)`

- The contract receives fewer than `amount` tokens but still increments `_totalSupply` and `_balances[_for]` by `amount`

- Withdraw the full credited balance and realize the deficit from pooled funds

*Round 1 | Agents: codex_1*

---

### F-003: Reward schedules can be underfunded because accounting trusts the requested transfer amount

**Confidence:** low | **Locations:** `onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:197, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:201, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:205, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:212, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:220, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:222`

`notifyRewardAmount()` computes a new `rewardRate` from the caller-supplied `_amount` before the reward token transfer occurs, and it never reconciles the actual amount received. If a reward token is fee-on-transfer, deflationary, or otherwise delivers less than `_amount`, the contract schedules rewards as though it received the full amount.

**Impact:** The pool can promise more rewards than it owns. Later reward claims may revert once accrued rewards exceed the actual token balance, creating a denial of service for reward collection; if the reward token matches the staking token, the shortfall can also bleed into principal liquidity.

**Paths:**

- Owner adds a reward token with transfer fees or deflationary behavior

- `rewardDistributor` calls `notifyRewardAmount(token, amount)`

- `_notifyReward()` sets `rewardRate` using `amount`, but `safeTransferFrom` delivers less than `amount`

- As rewards accrue, `getReward`/`getRewards` eventually try to transfer more tokens than the contract actually holds

*Round 1 | Agents: codex_1*

---

## Low (2)

### F-004: Reward-rate truncation permanently strands dust and can make small reward deposits entirely unclaimable

**Confidence:** high | **Locations:** `onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:197, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:201, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:205, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:208, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:222`

Reward emission uses integer division by `DURATION` when setting `rewardRate`, but the truncated remainder is never tracked or recoverable. If `_amount < DURATION`, `rewardRate` becomes zero and the transferred rewards are never emitted. Even for larger deposits, each top-up can leave residual dust permanently stranded in the contract.

**Impact:** Operators can accidentally lock reward tokens forever. For low-decimal reward tokens or small deposits, the full deposited reward amount may become unclaimable by users.

**Paths:**

- Call `notifyRewardAmount(token, amount)` with `amount < DURATION` in the token's base units

- `_notifyReward()` sets `rewardRate = amount / DURATION = 0`

- The reward tokens are still transferred into the contract

- No staker can ever accrue those tokens, and there is no recovery path for the stranded balance

*Round 1 | Agents: codex_1, opencode_1*

---

### F-005: Unbounded reward-token list can gas-brick staking, withdrawals, and reward claims

**Confidence:** high | **Locations:** `onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:26, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:70, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:170, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:171, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:264, onchain_auto/0xd2869042e12a3506100af1d192b5b04d65137941/contracts/StaxLPStaking.sol:267`

`rewardTokens` grows monotonically via `addReward()` and there is no cap or removal mechanism. Core user flows such as `stakeFor`, `_withdrawFor`, `getReward`, and `getRewards` all iterate over the entire array through `updateReward()` and/or `_getRewards()`. If enough reward tokens are added, these operations can exceed the block gas limit.

**Impact:** Users can be unable to stake, withdraw, or claim rewards because routine operations run out of gas. Since withdrawal paths also traverse the full list, staked funds can become practically stuck.

**Paths:**

- Owner repeatedly calls `addReward()` over time, growing `rewardTokens` without bound

- A user later calls `stake`, `withdraw`, `withdrawAll`, `getReward`, or `getRewards`

- The transaction loops over too many reward tokens in `updateReward()` and/or `_getRewards()`

- The call runs out of gas, preventing normal use of the staking contract

*Round 1 | Agents: codex_1, opencode_1*

---
