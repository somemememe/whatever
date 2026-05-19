# Audit Report

**Total findings:** 3

## Critical (1)

### F-001: ERC1155 mint callback reentrancy lets contract stakers mint the same pending points repeatedly

**Confidence:** high | **Locations:** `0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1111, 0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1576, 0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1581, 0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1596, 0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1601`

`deposit()` and `withdraw()` mint pending ERC1155 rewards before updating `user.rewardDebt`, and OpenZeppelin's `_mint()` performs an external `onERC1155Received` callback whenever the recipient is a contract. A malicious staking contract can reenter `deposit(_pid, 0)` or `withdraw(_pid, 0)` from that callback, recompute the same pending amount against the unchanged `rewardDebt`, and mint the same points repeatedly in one transaction.

**Impact:** An attacker can inflate their point balance arbitrarily without adding stake. If the points are redeemable elsewhere in the protocol, this becomes a direct drain of the value backing those points; otherwise, the reward system is permanently corrupted and honest users are diluted.

**Paths:**

- Attacker stakes through a contract that implements `IERC1155Receiver`.

- Rewards accrue for that contract's position.

- The attacker calls `deposit(_pid, 0)` or `withdraw(_pid, 0)`.

- `_mint()` invokes the attacker's `onERC1155Received` hook before `user.rewardDebt` is refreshed.

- The hook reenters `deposit(_pid, 0)` or `withdraw(_pid, 0)` and mints the same pending reward again.

- The attacker repeats until gas runs out, then exits with many times the legitimate points.

*Round 1 | Agents: codex_1*

---

## High (1)

### F-002: Pool accounting becomes insolvent with fee-on-transfer or balance-decreasing stake tokens

**Confidence:** high | **Locations:** `0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1539, 0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1563, 0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1587, 0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1589, 0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1607, 0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1621`

The farm credits `user.amount += _amount` based on the requested deposit amount instead of the tokens actually received, while reward accrual uses `pool.uToken.balanceOf(address(this))` as the live pool supply. For fee-on-transfer, deflationary, negative-rebase, or otherwise balance-decreasing stake tokens, internal shares diverge from the real token backing immediately.

**Impact:** A depositor can be credited for more stake than the farm actually holds, earn an outsized share of future points against the smaller real balance, and later withdraw more tokens than were ever received. The resulting shortfall is paid by later depositors if available; otherwise withdrawals or emergency withdrawals start reverting because the pool is undercollateralized.

**Paths:**

- A pool is added for a token that taxes transfers or can reduce balances independently.

- An attacker deposits 100 tokens; the farm receives less than 100 but still records the full 100 in `user.amount`.

- Subsequent rewards are divided by the smaller live `balanceOf(address(this))`, so the attacker accrues too many points.

- When the attacker later withdraws or emergency-withdraws, the contract attempts to transfer the full recorded amount, consuming other users' liquidity or reverting once the shortfall is exposed.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-003: Reward parameter changes retroactively rewrite past emissions for untouched pools

**Confidence:** high | **Locations:** `0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1516, 0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1530, 0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1558, 0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1568, 0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1626, 0xd3c41c85be295607e8ea5c58487ec5894300ee67/Contract.sol:1630`

`setMintRules()` and `setStartBlock()` mutate global emission parameters without checkpointing existing pools first. `updatePool()` later settles the entire interval since `pool.lastRewardBlock` using the latest `pointsPerBlock`, and pools created before a start-block change keep their old `lastRewardBlock`. As a result, changing the reward rate or postponing/advancing the start can retroactively reprice already elapsed blocks instead of only affecting future emissions.

**Impact:** Using the admin setters as intended can overmint or undermint points for historical periods. Users can receive windfall rewards or lose rewards they should have earned depending on when the next pool update happens, and if points have redemption value this translates directly into economic loss or unexpected inflation.

**Paths:**

- A pool has not been updated for several blocks, so `pool.lastRewardBlock` is stale.

- Before anyone touches the pool, the owner changes `pointsPerBlock` via `setMintRules()`.

- The next `updatePool()` computes rewards for the full stale interval with the new rate, retroactively overpaying or underpaying that entire period.

- Separately, a pool can be added before farming starts, storing the old `startBlock` as `lastRewardBlock`. If the owner later changes `startBlock`, the pool still settles from the old value, causing pre-start overminting or missed rewards once updates begin.

*Round 1 | Agents: *

---
