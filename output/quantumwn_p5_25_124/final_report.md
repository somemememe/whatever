# Audit Report

**Total findings:** 4

## High (2)

### F-001: Unchecked ERC20 return values can mint unbacked stake receipts or release QWA without burning sQWA

**Confidence:** high | **Locations:** `0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:65-66, 0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:74-79`

`stake()` and `unstake()` call `transfer`/`transferFrom` on `QWA` and `sQWA` but never check the returned boolean. With any token implementation that signals failure by returning `false` instead of reverting, execution continues as if the transfer succeeded.

**Impact:** A failed `QWA.transferFrom` during `stake()` can still hand out sQWA without the pool receiving backing assets. A failed `sQWA.transferFrom` during `unstake()` can still release QWA without actually collecting sQWA. Conversely, a failed outgoing transfer can confiscate user assets by taking one side of the exchange without delivering the other.

**Paths:**

- Call `stake()` when `QWA.transferFrom(msg.sender, address(this), amount)` returns `false`; the function still executes `sQWA.transfer(to, amount)` and creates an unbacked claim.

- Call `unstake()` when `sQWA.transferFrom(msg.sender, address(this), amount)` returns `false`; the function can still pass the balance check and execute `QWA.transfer(to, amount)`.

- Call `unstake()` or `stake()` when the outgoing token transfer returns `false`; the function finishes without delivering the expected asset, leaving the user or pool shorted.

*Round 1 | Agents: codex_1*

---

### F-002: Missed-epoch rewards can be captured by late entrants because `rebase()` only catches up one epoch per call

**Confidence:** high | **Locations:** `0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:63-66, 0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:83-100`

When the contract is multiple epochs behind, `rebase()` performs only a single rebase and advances `epoch.end` by only one `epoch.length`. `stake()` calls this one-step catch-up before accepting a new deposit, so a user can join after long inactivity but before the remaining overdue rebases are processed, then share rewards that economically accrued before their entry.

**Impact:** Historical rewards intended for existing stakers can be diluted and partially stolen by a late staker. The more epochs the contract has missed, the larger the backlog a new entrant can capture.

**Paths:**

- Let several epochs pass without successful `rebase()` calls while excess QWA accumulates in the staking contract or via distributor funding.

- Call `stake()`: it processes only one overdue epoch, then accepts the new deposit and mints sQWA to the new entrant.

- Call `rebase()` again until the backlog is caught up; the new entrant now participates in distributing pre-entry excess QWA and can `unstake()` with a share of those historical rewards.

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-003: Predictable epoch boundaries enable just-in-time staking to siphon epoch rewards

**Confidence:** medium | **Locations:** `0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:63-66, 0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:83-100`

Rewards are allocated to whoever is in `sQWA.circulatingSupply()` when `rebase()` runs, but the contract has no warmup period, minimum staking duration, or time-weighting. A large holder can enter shortly before an epoch rollover, be included in that rebase, and exit immediately after.

**Impact:** Sophisticated actors can farm emissions with minimal exposure while long-term stakers are diluted. This creates a repeatable economic extraction strategy around every predictable epoch boundary.

**Paths:**

- Stake a large amount shortly before `epoch.end`.

- Trigger or wait for the next `rebase()` so the temporary position is included in the reward split.

- Unstake immediately after the rebase to realize a disproportionate share of that epoch's reward despite only being exposed briefly.

*Round 1 | Agents: codex_1*

---

### F-004: Nominal-amount accounting can undercollateralize the pool if QWA transfers less than the requested amount

**Confidence:** low | **Locations:** `0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:65-66, 0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:74-79, 0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:94-100`

`stake()` assumes `_amount` QWA arrived and credits `_amount` sQWA without checking the actual balance delta. If the configured QWA token ever burns, taxes, short-transfers, or otherwise credits less than requested, the contract still issues the full nominal receipt amount.

**Impact:** Each discounted deposit can mint more sQWA than the pool actually received, making the staking pool undercollateralized and shifting the loss to existing stakers or future withdrawers.

**Paths:**

- Use a QWA token implementation that charges transfer fees, burns on transfer, or credits less than the requested amount.

- Call `stake(amount)`; the staking contract receives less than `amount` but still transfers `amount` sQWA to the staker.

- Repeat or later `unstake()` to realize claims on more QWA than was ever contributed, pushing insolvency onto the pool.

*Round 1 | Agents: codex_1*

---
