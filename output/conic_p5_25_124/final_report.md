# Audit Report

**Total findings:** 4

## High (2)

### F-001: First staker after a zero-stake interval can capture all rewards accrued while nobody was staked

**Confidence:** high | **Locations:** `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:79, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:101, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:183`

`poolCheckpoint()` computes newly accrued CRV/CVX/CNC against `lastHoldings`, but when `controller.lpTokenStaker().getBalanceForPool(pool)` is zero it skips `_updateEarned()` and therefore does not advance `lastHoldings`. Rewards that accrue during a zero-stake interval remain unassigned and are later distributed across the next non-zero staked supply, letting the first new staker absorb the entire backlog.

**Impact:** A user can stake a dust amount after an idle period and appropriate all rewards that accumulated while no one was staked. This diverts materially valuable CRV/CVX/CNC from the intended reward flow and creates a permissionless reward-theft/windfall vector.

**Paths:**

- All LP staking for a pool drops to zero while the pool's Curve/Convex positions continue accruing rewards.

- No one calls a path that advances `lastHoldings` during the zero-stake interval, so the backlog remains pending.

- An attacker stakes a minimal amount and triggers `accountCheckpoint()` or `claimEarnings()`, causing the full backlog to be distributed over the tiny current staked supply.

*Round 1 | Agents: codex_1*

---

### F-002: Selling extra rewards double-counts the received CNC and can make reward accounting insolvent

**Confidence:** high | **Locations:** `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:79, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:137, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:245, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:252, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:255`

`_claimPoolEarningsAndSellRewardTokens()` adds CNC obtained from selling extra rewards directly into `_rewardsMeta[_CNC_KEY].earnedIntegral`, but it never updates `_rewardsMeta[_CNC_KEY].lastHoldings` to include that freshly received CNC. The next `poolCheckpoint()` therefore sees the same CNC balance increase again and credits it a second time as newly earned CNC.

**Impact:** CNC liabilities can exceed the CNC actually held by the pool. Early claimers can over-withdraw CNC at the expense of later users, and later claims can revert once the accounting promises more CNC than the pool possesses.

**Paths:**

- A caller triggers `claimPoolEarningsAndSellRewardTokens()` after extra rewards have accrued.

- The swap sends CNC to the pool and `_claimPoolEarningsAndSellRewardTokens()` increments the CNC integral once.

- Because `lastHoldings` was not updated, a later `poolCheckpoint()`/`claimEarnings()` credits the same CNC a second time.

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-003: Extra reward tokens are claimed to the pool but sold only from the reward manager, leaving accrued extras trapped

**Confidence:** high | **Locations:** `0x635228edaead8a76b6ae1779bd7682043321943d/ConvexHandlerV3.sol:76, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:245, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:279, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:399`

Convex extra rewards are claimed with `getReward(_conicPool, true)`, which sends them to the Conic pool address, but the subsequent sale path in `RewardManagerV2` only swaps `IERC20(rewardToken_).balanceOf(address(this))`, i.e. balances held by the reward manager itself. Since the normal accrual path deposits extras into the pool rather than the reward manager, `claimPoolEarningsAndSellRewardTokens()` does not actually sell the earned extra rewards.

**Impact:** Non-CRV/CVX extra rewards can accumulate inside `ConicEthPool` without being converted into CNC or otherwise distributed, causing permanent reward-value lockup and reducing yield for LPs.

**Paths:**

- A listed Curve/Convex reward pool accrues an extra reward token.

- `RewardManagerV2._claimPoolEarnings()` claims rewards through `ConvexHandlerV3`, which directs them to `pool`.

- `RewardManagerV2._sellRewardTokens()` checks only the reward manager's token balances, finds zero, and leaves the accrued extra rewards stranded in the pool.

*Round 1 | Agents: merge_review*

---

### F-004: Rebalancing rewards can be farmed with temporary capital because only deposits are rewarded

**Confidence:** medium | **Locations:** `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol:136, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol:183, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol:344, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol:829, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol:846`

`depositFor()` calls `_handleRebalancingRewards()` and forwards the pre/post deviation improvement to `inflationManager.handleRebalancingRewards(...)`, but `withdraw()` never applies a symmetric penalty, clawback, or minimum holding period if the same liquidity is immediately removed and the imbalance returns. Reward eligibility is therefore tied only to a transient improvement at deposit time.

**Impact:** If the inflation manager pays or records CNC rewards immediately, an attacker can use flash-loaned or other temporary capital to harvest rebalancing incentives without providing lasting balance improvements, draining CNC emissions intended for genuine rebalancers.

**Paths:**

- A weight update leaves the pool imbalanced and sets `rebalancingRewardActive = true`.

- An attacker deposits temporary capital so the routing logic pushes funds into underweight Curve pools and `handleRebalancingRewards` credits them for the improved deviation.

- The attacker promptly exits through `unstakeAndWithdraw`/`withdraw`, restoring the imbalance while retaining the reward.

*Round 1 | Agents: codex_1*

---
