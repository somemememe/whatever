# Audit Report

**Total findings:** 5

## High (3)

### F-001: Unchecked ERC20 return values let stake and unstake proceed even when token transfers silently fail

**Confidence:** medium | **Locations:** `0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:334, 0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:335, 0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:343, 0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:348`

`stake()` and `unstake()` invoke `TOKEN.transferFrom`, `sTOKEN.transfer`, `sTOKEN.transferFrom`, and `TOKEN.transfer` without checking their boolean return values. If either configured token signals failure by returning `false` instead of reverting, the function continues as though the transfer succeeded.

**Impact:** Silent transfer failures can break the 1:1 backing invariant. A caller can be credited sTOKEN without depositing TOKEN, or withdraw TOKEN without actually surrendering sTOKEN, creating direct reserve theft or user fund loss depending on which transfer silently fails.

**Paths:**

- Call `stake(_to, amount)` with a TOKEN implementation that returns `false` from `transferFrom`; the function still executes `sTOKEN.transfer(_to, amount)` and credits the user without receiving backing TOKEN.

- Call `unstake(_to, amount, false)` with an sTOKEN implementation that returns `false` from `transferFrom`; the function still reaches `TOKEN.transfer(_to, amount)` and pays out without actually taking in the receipt tokens.

- Call `unstake(_to, amount, false)` where `TOKEN.transfer` returns `false`; the user has already transferred in sTOKEN, but receives no TOKEN while the transaction itself does not revert.

*Round 1 | Agents: codex_1*

---

### F-002: Nominal-amount accounting makes the pool insolvent against fee-on-transfer or deflationary tokens

**Confidence:** medium | **Locations:** `0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:334, 0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:335, 0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:343, 0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:348`

The contract always credits and redeems the caller-supplied `_amount` rather than measuring the actual balance delta of TOKEN or sTOKEN. If either token burns, taxes, or otherwise transfers fewer units than requested, `stake()` and `unstake()` still mint or redeem the full nominal amount.

**Impact:** If TOKEN or sTOKEN is deflationary, users can be over-credited on entry or overpaid on exit, leaving the staking pool undercollateralized and enabling reserve drainage over repeated operations.

**Paths:**

- If TOKEN charges a transfer fee, staking `100` may deliver only `90` TOKEN to the contract while the user still receives `100` sTOKEN.

- If sTOKEN charges a fee on `transferFrom`, unstaking `100` may transfer in only `90` sTOKEN while the contract still pays out `100` TOKEN.

*Round 1 | Agents: codex_1*

---

### F-003: Reentrant distributor can apply the same epoch reward multiple times before `epoch.distribute` is refreshed

**Confidence:** medium | **Locations:** `0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:352, 0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:354, 0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:356, 0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:359, 0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:360, 0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:363, 0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:369`

`rebase()` makes an external call to `distributor.distribute()` before recomputing `epoch.distribute`, and there is no reentrancy guard. If the contract is at least one extra epoch behind, a malicious or compromised distributor can reenter `rebase()` while `epoch.end <= block.timestamp`, causing `sTOKEN.rebase(epoch.distribute, epoch.number)` to be executed again using the stale distribution amount.

**Impact:** The same pending reward can be rebased multiple times against the same backing, inflating sTOKEN supply and creating an insolvency gap that is realized when holders redeem for TOKEN.

**Paths:**

- Allow the staking contract to become at least two epochs overdue so that after `epoch.end = epoch.end + epoch.length`, the updated `epoch.end` is still not in the future.

- Trigger `rebase()` when `epoch.distribute` is positive and a distributor is configured.

- During `distributor.distribute()`, reenter `rebase()`; the nested call executes another `sTOKEN.rebase` using the stale `epoch.distribute` before the outer call recalculates it from actual balances.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-004: Missing validation for zero epoch length allows unbounded same-timestamp rebases after the first epoch

**Confidence:** high | **Locations:** `0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:311, 0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:320, 0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:356`

The constructor does not enforce `_epochLength > 0`. If the contract is deployed with `epoch.length == 0`, each call to `rebase()` leaves `epoch.end` unchanged because it performs `epoch.end = epoch.end + epoch.length`.

**Impact:** Once the first epoch starts, anyone can call `rebase()` repeatedly in the same timestamp window, rapidly advancing epoch numbers and repeatedly invoking reward distribution logic, distorting or accelerating emissions far beyond the intended schedule.

**Paths:**

- Deploy the contract with `_epochLength = 0`.

- Wait until `block.timestamp >= epoch.end`.

- Call `rebase()` repeatedly; each call still satisfies `epoch.end <= block.timestamp` because `epoch.end` never advances.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-005: `secondsToNextEpoch()` reverts when the epoch is overdue

**Confidence:** high | **Locations:** `0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:398, 0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol:399`

`secondsToNextEpoch()` returns `epoch.end - block.timestamp` without handling the case where the current time has already passed `epoch.end`. Under Solidity 0.8.x, that subtraction underflows and reverts.

**Impact:** On-chain or off-chain integrations that query the countdown can be denied service exactly when the epoch is late and the value is most likely to be queried.

**Paths:**

- Allow `block.timestamp` to exceed `epoch.end` without calling `rebase()`.

- Call `secondsToNextEpoch()`; the subtraction underflows and the view function reverts.

*Round 1 | Agents: codex_1*

---
