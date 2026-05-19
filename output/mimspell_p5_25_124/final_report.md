# Audit Report

**Total findings:** 2

## Critical (1)

### F-001: Unchecked 0x calldata plus unlimited underlying approval lets the caller redirect redeemed collateral away from MIM

**Confidence:** high | **Locations:** `0xa5564a2d1190a141cac438c9fde686ac48a18a79/src/swappers/ZeroXStargateLPSwapper.sol:45, 0xa5564a2d1190a141cac438c9fde686ac48a18a79/src/swappers/ZeroXStargateLPSwapper.sol:53, 0xa5564a2d1190a141cac438c9fde686ac48a18a79/src/swappers/ZeroXStargateLPSwapper.sol:54, 0xa5564a2d1190a141cac438c9fde686ac48a18a79/src/swappers/ZeroXStargateLPSwapper.sol:64, 0xa5564a2d1190a141cac438c9fde686ac48a18a79/src/swappers/ZeroXStargateLPSwapper.sol:68, 0xa5564a2d1190a141cac438c9fde686ac48a18a79/src/swappers/ZeroXStargateLPSwapper.sol:73`

The swapper gives `zeroXExchangeProxy` an infinite allowance over the Stargate pool's underlying token, then forwards fully caller-controlled `swapData` to that proxy with a raw `call()` and never verifies that the approved underlying was swapped into MIM for the swapper itself. Because the function also accepts caller-controlled `recipient` and only enforces the minimum output through `shareToMin`, a malicious caller can redeem LP into underlying, have the 0x proxy spend that underlying into an attacker-controlled payout path or non-MIM asset, and set `shareToMin = 0` so the final BentoBox deposit of the remaining MIM balance does not revert.

**Impact:** Collateral routed through this swapper can be turned into attacker-owned assets instead of protocol-owned MIM, causing direct theft of the full redeemed position and leaving the liquidation/deleverage flow undercollateralized.

**Paths:**

- LP shares are placed on the swapper through the intended liquidation/deleverage flow or are already present on the contract.

- The caller invokes `swap()` with malicious `swapData` that makes `zeroXExchangeProxy` spend the swapper's redeemed underlying through its unlimited allowance while routing the bought assets away from the swapper or into a non-MIM token.

- The caller sets `shareToMin` to `0`, so `bentoBox.deposit()` accepts the swapper's remaining MIM balance even if it is zero, and the transaction completes after the collateral has been redirected.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-003: Any balances parked on the swapper can be swept to an arbitrary recipient by the next caller

**Confidence:** high | **Locations:** `0xa5564a2d1190a141cac438c9fde686ac48a18a79/src/swappers/ZeroXStargateLPSwapper.sol:53, 0xa5564a2d1190a141cac438c9fde686ac48a18a79/src/swappers/ZeroXStargateLPSwapper.sol:58, 0xa5564a2d1190a141cac438c9fde686ac48a18a79/src/swappers/ZeroXStargateLPSwapper.sol:61, 0xa5564a2d1190a141cac438c9fde686ac48a18a79/src/swappers/ZeroXStargateLPSwapper.sol:73`

`swap()` is permissionless, always operates on the swapper's own balances, and sends the resulting BentoBox shares to an arbitrary caller-supplied `recipient`. It withdraws BentoBox shares from `address(this)`, redeems the contract's entire LP token balance with `pool.balanceOf(address(this))`, and deposits the contract's entire MIM balance with `mim.balanceOf(address(this))`. As a result, any BentoBox LP shares previously credited to the swapper, or any LP/MIM already sitting on the contract from an earlier step, accidental transfer, or stranded dust, are claimable by whoever calls `swap()` first.

**Impact:** If collateral or proceeds are ever staged on the swapper across transactions, front-run, or stranded there operationally, a third party can convert and redirect those assets to themselves. This turns temporary custody mistakes into direct fund loss.

**Paths:**

- BentoBox LP shares are credited to the swapper, or LP/MIM tokens are left on the swapper contract from an earlier operation or accidental transfer.

- An attacker calls `swap()` before the intended actor and sets `recipient` to an address they control, choosing any valid `swapData` for the redeem/swap leg.

- The swapper withdraws/redeems/deposits its full balances and credits the resulting MIM shares to the attacker's chosen recipient.

*Round 1 | Agents: codex_1*

---
