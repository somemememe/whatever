# Audit Report

**Total findings:** 7

## High (3)

### F-001: Privileged wallets receive all LP tokens and can withdraw pooled liquidity

**Confidence:** high | **Locations:** `0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:665-678, 0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:831-840`

`startTrading()` sends the entire initial LP position to `owner()`, and `_addLiquidity()` sends all fee-funded LP tokens to `_swapFeeReceiver` instead of locking or burning them.

**Impact:** Whoever controls those LP tokens can remove the pool liquidity at any time and extract the paired ETH/tokens, collapsing market liquidity and imposing direct losses on traders and holders.

**Paths:**

- A privileged caller starts trading, receives the initial LP tokens via `addLiquidityETH(..., owner(), ...)`, then removes liquidity from the pair off-contract.

- Later fee-funded auto-liquidity mints additional LP tokens to `_swapFeeReceiver`, who can also withdraw that protocol-funded liquidity.

*Round 1 | Agents: codex_1*

---

### F-002: Reward-cap enforcement is broken, allowing over-minting past `maxSupply` and stranding later stakers

**Confidence:** high | **Locations:** `0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:946-947, 0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:966-976, 0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:985-998`

`claim()` only checks `totalSupply() <= maxSupply` before minting and never verifies `totalSupply() + reward <= maxSupply`, so a single claim can push supply past the advertised cap. After that, `unstake()` pays rewards only when `totalSupply() + reward < maxSupply`, otherwise users get principal only.

**Impact:** An early or large staker can consume the remaining reward headroom and mint the token supply beyond `maxSupply`, diluting holders. Once the cap has been crossed or nearly exhausted, later stakers can be unable to realize accrued rewards and may recover only principal on exit.

**Paths:**

- A staker waits until total supply is near `maxSupply`, then calls `claim()` and mints a reward that pushes supply beyond the cap.

- Subsequent stakers attempting to claim hit the cap check, and `unstake()` falls back to minting only principal when the reward branch is no longer allowed.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-003: Owner or fee receiver can erase all pending staking yield by disabling staking

**Confidence:** high | **Locations:** `0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:611-618, 0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:966-980, 0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:985-998, 0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:1024-1025`

`setStakingState(false)` is callable by either `owner()` or `_swapFeeReceiver`. Once staking is disabled, users can no longer call `claim()`, and `unstake()` only pays rewards when `stakingEnabled` is still true.

**Impact:** A privileged actor can zero out every staker's accrued but unclaimed rewards in one transaction, forcing users to exit with principal only and causing direct economic loss across all open positions.

**Paths:**

- The owner or `_swapFeeReceiver` calls `setStakingState(false)`.

- Existing stakers are then blocked by `isStakingEnabled` in `claim()`, and `unstake()` executes its principal-only branch because `stakingEnabled` is false.

*Round 1 | Agents: codex_1*

---

## Medium (3)

### F-004: Previous operator keeps team-level powers after ownership transfer or renounce

**Confidence:** high | **Locations:** `0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:426-432, 0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:611-613, 0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:643, 0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:691-713, 0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:886-887, 0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:1009-1025`

Privileged functions use the `teamOROwner` modifier, but `_swapFeeReceiver` is initialized once and is not updated when ownership changes. A prior owner who remains `_swapFeeReceiver` keeps the same team-level powers even after `transferOwnership()` or `renounceOwnership()`.

**Impact:** The project can appear to hand over or renounce control while the previous operator still retains meaningful authority, including changing the fee receiver, toggling staking, excluding addresses from fees, forcing swaps, and creating validators.

**Paths:**

- The deployer transfers or renounces ownership but remains stored in `_swapFeeReceiver`.

- That address continues passing `teamOROwner` and can still exercise privileged control until someone explicitly rotates `_swapFeeReceiver`.

*Round 1 | Agents: codex_1*

---

### F-005: Setting fees to zero bricks taxed AMM transfers through division by zero

**Confidence:** medium | **Locations:** `0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:698-705, 0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:798-803`

`updateFees()` allows the owner to set all fee components to zero, which makes `totalFees == 0`. When a buy or sell later enters the fee path, `_transfer()` still executes `_tokensForLiquidity += fees * _liquidityFee / totalFees` and the analogous divisions, reverting on division by zero.

**Impact:** A legitimate fee-disable operation can unintentionally make taxed AMM buys and sells revert until the owner restores a nonzero fee configuration, creating a permissionless trading DoS on the pool.

**Paths:**

- The owner calls `updateFees(0, 0, 0)`, setting `totalFees` to zero.

- A non-exempt user then buys from or sells to the AMM pair; `takeFee` is true, `_transfer()` reaches the fee-splitting math, and the transaction reverts on division by zero.

*Round 1 | Agents: opencode_1*

---

### F-006: Zero-slippage fee swaps are sandwichable and leak fee value to MEV

**Confidence:** medium | **Locations:** `0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:777-785, 0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:815-828, 0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:831-840`

`swapBack()` sells accumulated fee tokens with `amountOutMin = 0` and adds liquidity with zero minimum amounts. Because this path is triggered inside ordinary transfers once the threshold is reached, searchers can predict and price-manipulate the contract's forced trades.

**Impact:** MEV searchers can sandwich the contract's fee conversions, extract value from accumulated fees, and worsen price impact for the user whose transfer triggers the swap.

**Paths:**

- An attacker monitors the mempool for a transfer that will execute `swapBack()` after `contractTokenBalance >= swapTokensThreshold`.

- The attacker front-runs to skew the pool price, lets the contract perform its zero-protection swap and liquidity add, then back-runs to capture the spread.

*Round 1 | Agents: codex_1, opencode_1*

---

## Low (1)

### F-007: `userEarned()` mixes the queried account with `msg.sender`'s cached rewards

**Confidence:** high | **Locations:** `0x4ae2cd1f5b8806a973953b76f9ce6d5fab9cdcfd/Contract.sol:920-925`

`userEarned(staker, validator)` computes current rewards for the `staker` parameter but reads cached prior rewards from `_stakers[msg.sender][validator].earned` instead of `_stakers[staker][validator].earned`.

**Impact:** Third-party reward queries can return materially incorrect figures, which can mislead frontends, monitoring, and users assessing another account's accrued rewards.

**Paths:**

- A caller invokes `userEarned(victim, validator)`.

- The function combines `victim`'s live accrual with the caller's cached `earned` value, producing a mixed and incorrect result.

*Round 1 | Agents: codex_1, opencode_1*

---
