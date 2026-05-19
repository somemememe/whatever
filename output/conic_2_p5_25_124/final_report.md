# Audit Report

**Total findings:** 4

## High (2)

### F-001: First staker after a zero-stake interval can appropriate the entire uncheckpointed reward backlog

**Confidence:** high | **Locations:** `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:79, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:101, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:136, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:183`

`poolCheckpoint()` computes newly accrued CRV/CVX/CNC from current holdings, but it only advances `earnedIntegral` and `lastHoldings` inside `_updateEarned()`, which is skipped whenever `getBalanceForPool(pool) == 0`. Rewards can therefore keep accruing while no LP tokens are staked without ever being checkpointed. Once any account stakes and later hits `_accountCheckpoint()`/`claimEarnings()`, the entire backlog is divided by the now-nonzero staked supply and can be assigned almost entirely to that first staker.

**Impact:** A dust staker can capture all rewards that accumulated while the staking supply was zero, extracting CRV, CVX, and CNC value out of the pool’s reward stream with negligible capital.

**Paths:**

- All LP stakers leave so `controller.lpTokenStaker().getBalanceForPool(pool)` becomes zero while pool-level rewards continue accruing.

- One attacker stakes a minimal amount of LP tokens.

- The attacker calls `claimEarnings()` or otherwise triggers `_accountCheckpoint()`.

- `poolCheckpoint()` allocates the full previously uncheckpointed backlog against the attacker’s tiny stake, after which the attacker can claim it.

*Round 1 | Agents: codex_1*

---

### F-002: Convex extra rewards are claimed to the pool, but the sale path only swaps RewardManager-held balances

**Confidence:** high | **Locations:** `0x635228edaead8a76b6ae1779bd7682043321943d/ConvexHandlerV3.sol:74, 0x635228edaead8a76b6ae1779bd7682043321943d/ConvexHandlerV3.sol:76, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:245, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:250, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:309, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:398`

Convex claims are executed as `getReward(_conicPool, true)`, so CRV/CVX and all extra reward tokens are delivered to the Conic pool address. However, `_sellRewardTokens()` only inspects `IERC20(rewardToken_).balanceOf(address(this))`, i.e. balances held by `RewardManagerV2` itself. The code never transfers extra reward tokens from the pool into `RewardManagerV2`, and the pool only pre-approves CRV/CVX/CNC to the reward manager. As a result, listed extra reward tokens are never reachable by the swap logic and remain stranded on the pool contract.

**Impact:** Any Convex extra reward stream configured through `addExtraReward()` becomes permanently unrealizable for stakers, causing lasting loss of protocol yield.

**Paths:**

- Governance lists an extra reward token via `addExtraReward()`.

- Convex distributes that token during `getReward(_conicPool, true)`, sending it to the pool contract.

- `claimPoolEarningsAndSellRewardTokens()` runs `_sellRewardTokens()`, but `_swapRewardTokenForWeth()` sees zero balance on `RewardManagerV2` and does nothing.

- The extra reward tokens remain stuck on the pool with no in-scope path to swap or distribute them.

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-003: Floor-rounded weight rescaling can leave no valid deposit target while rebalancing is active

**Confidence:** high | **Locations:** `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol:234, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol:254, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol:263, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol:610, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol:614, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol:618, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol:889`

`_setWeightToZero()` rescales the surviving weights with `divDown`/`mulDown`, so the post-rescale weights can sum to slightly less than `1e18`. When `rebalancingRewardActive` is true, `_getMaxDeviation()` returns zero, so `_getDepositPool()` only accepts deposits into pools that are still strictly below their exact rounded target. After those rounded targets are filled, any residual deposit amount above the hardcoded 100-unit tolerance has nowhere to go and `_getDepositPool()` reverts with `error retrieving deposit pool`.

**Impact:** After permissionless emergency weight changes, the pool can enter a state where fresh deposits revert until governance manually resets weights, degrading availability during a stressed rebalancing period.

**Paths:**

- A curve pool is zeroed out through `handleDepeggedCurvePool()`, which calls `_setWeightToZero()` and enables `rebalancingRewardActive`.

- Floor rounding causes the surviving weights to sum to less than `1e18`.

- A later deposit fills every surviving pool up to its exact rounded target while `_getMaxDeviation()` is zero.

- If the leftover residue exceeds the 100-unit tolerance, the next `_getDepositPool()` call finds no eligible pool and the deposit reverts.

*Round 1 | Agents: codex_1*

---

### F-004: Standalone reward-token sales can over-credit CNC because sold CNC is added to the integral without syncing `lastHoldings`

**Confidence:** high | **Locations:** `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:79, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:101, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:136, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:239, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:245, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:252, 0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol:255`

`claimPoolEarningsAndSellRewardTokens()` first runs `poolCheckpoint()`, then `_claimPoolEarningsAndSellRewardTokens()` sells extra rewards into CNC and immediately credits `receivedCnc_ / totalStaked` into `_rewardsMeta[_CNC_KEY].earnedIntegral`. That helper does not advance `_rewardsMeta[_CNC_KEY].lastHoldings`, so the sold CNC still appears as fresh `cncEarned` on the next `poolCheckpoint()` and is added to the integral a second time. The user-facing `claimEarnings()` path later resynchronizes `lastHoldings`, so the double count is specifically exposed through the standalone claim/sell path and the fee-triggered internal claim path.

**Impact:** CNC rewards can be overstated relative to the pool’s actual CNC balance, eventually causing reward insolvency or failed claims for later users.

**Paths:**

- Someone calls `claimPoolEarningsAndSellRewardTokens()` directly, or `poolCheckpoint()` internally reaches `_claimPoolEarningsAndSellRewardTokens()` while collecting fees.

- Extra reward tokens are sold and the received CNC is added directly to `earnedIntegral`.

- `lastHoldings` remains at its pre-sale value.

- The next `poolCheckpoint()` counts the same CNC balance delta again and credits it a second time to stakers.

*Round 1 | Agents: codex_1*

---
