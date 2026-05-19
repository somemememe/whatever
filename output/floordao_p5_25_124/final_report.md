# Audit Report

**Total findings:** 3

## Critical (1)

### F-001: Warmup deposits are rebased but never counted as liabilities, allowing staking insolvency

**Confidence:** high | **Locations:** `0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:94, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:104, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:111, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:133, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:135, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:233, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:234, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:238, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:279`

`stake()` transfers FLOOR into the contract and records warmup positions as `deposit` plus `gons`, while `claim()` later pays `sFLOOR.balanceForGons(info.gons)`, so warmup balances continue to appreciate with rebases. However, `rebase()` computes distributable surplus from `FLOOR.balanceOf(address(this)) - sFLOOR.circulatingSupply() - bounty` and never subtracts `gonsInWarmup` or `supplyInWarmup()`. Warmup-backed FLOOR is therefore treated as free excess reserves and redistributed to current stakers even though it is still owed to warmup claimants.

**Impact:** Large warmup balances can make the system undercollateralized. After one or more rebases, the contract can owe more sFLOOR/gFLOOR/FLOOR than it holds backing for, causing honest claimants or unstakers to receive unbacked positions or hit `unstake()` reverts due to insufficient FLOOR reserves.

**Paths:**

- Set `warmupPeriod > 0` and let some users already hold active staking positions.

- A user stakes FLOOR into warmup, increasing `gonsInWarmup` but not `sFLOOR.circulatingSupply()`.

- When `rebase()` runs, the newly deposited FLOOR is included in `balance` and treated as surplus because warmup liabilities are not subtracted.

- Existing stakers receive that value through rebases, while the warmup user still retains a claim for `sFLOOR.balanceForGons(info.gons)`.

- Total redeemable claims eventually exceed the contract's FLOOR backing, and withdrawals start failing.

*Round 1 | Agents: codex_1*

---

## High (1)

### F-003: An opted-in warmup position can be locked indefinitely because every added stake resets the entire expiry

**Confidence:** high | **Locations:** `0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:99, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:100, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:104, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:105, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:106, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:107, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:158, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:159`

Whenever a new stake is added to an address already in warmup, the contract overwrites `expiry` with `epoch.number + warmupPeriod` for the entire aggregated claim instead of tracking a separate tranche. Once an account allows external actions, a third party can keep resetting the maturity of the victim's full position by staking again just before expiry. This is especially cheap because `stake()` has no `_amount > 0` check, so a zero-value or dust call can refresh the timer. The risk is amplified by `toggleLock()` being documented as protection even though `lock = true` is the state that actually permits third-party stake/claim activity.

**Impact:** A victim's entire warmup balance can be denied indefinitely for negligible attacker cost. Users who toggle the flag expecting protection can unintentionally opt themselves into a permissionless lockup attack.

**Paths:**

- A victim has a nonzero warmup position and either intentionally enables external actions or calls `toggleLock()` believing it will block them.

- Shortly before the position matures, an attacker calls `stake(victim, 0, ..., false)` or stakes a dust amount.

- The contract aggregates the new stake into the existing claim and resets `expiry` for the whole position.

- Repeating the call each epoch prevents the victim from ever reaching a claimable state.

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (1)

### F-002: Rebase accounting relies on external `circulatingSupply()` semantics to include wrapped gFLOOR liabilities

**Confidence:** low | **Locations:** `0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:199, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:200, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:201, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:202, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:211, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:213, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:214, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:233, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:234, 0x759c6de5bca9ade8a1a2719a31553c4b7de02539/contracts/Staking.sol:238`

`wrap()` pulls sFLOOR into the staking contract and mints external gFLOOR claims, while `unwrap()` burns gFLOOR and releases the backing sFLOOR. `rebase()` does not track any wrapped-liability term locally and instead assumes that `sFLOOR.circulatingSupply()` already includes the sFLOOR held in staking on behalf of gFLOOR holders. If that external implementation excludes staking-held balances, wrapped positions are treated as excess backing and can be over-distributed during rebases.

**Impact:** If the linked sFLOOR implementation does not fold wrapped supply back into `circulatingSupply()`, gFLOOR holders can become undercollateralized over time and eventually be unable to fully unwrap or exit.

**Paths:**

- Users wrap a large amount of sFLOOR into gFLOOR, moving the sFLOOR backing into the staking contract.

- A later `rebase()` subtracts only `sFLOOR.circulatingSupply()` from the contract's FLOOR reserves.

- If `circulatingSupply()` excludes the staking-held wrapper backing, those already-encumbered assets are mistaken for surplus.

- Rebases distribute that surplus to other stakers, leaving gFLOOR claims progressively underbacked.

*Round 1 | Agents: codex_1*

---
