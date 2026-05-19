# Audit Report

**Total findings:** 3

## Critical (1)

### F-001: Swap invariant is weakened by a 100x scaling mismatch, allowing near-total reserve drains

**Confidence:** high | **Locations:** `0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol:403, 0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol:404, 0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol:405`

The swap check multiplies post-swap balances by 10000 and subtracts a 15 bp fee, but compares against `_reserve0 * _reserve1 * 1000**2` instead of `10000**2`. This reduces the required post-swap product to roughly 1% of the intended invariant.

**Impact:** An attacker can satisfy the `K` check while extracting nearly the entire opposite-side reserve with minimal input, causing direct and repeatable pool drains.

**Paths:**

- Seed or target a pool with meaningful reserves.

- Call `swap()` with a small input on one side and request almost all liquidity from the other side.

- Because the right-hand side of the invariant is under-scaled by 100x, the transaction passes even though the real constant-product condition is badly violated.

*Round 1 | Agents: codex_1*

---

## High (1)

### F-002: Referral fee transfers are excluded from reserve accounting, corrupting reserves after swaps

**Confidence:** high | **Locations:** `0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol:379, 0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol:380, 0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol:391, 0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol:397, 0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol:408, 0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol:320, 0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol:321, 0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol:416, 0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol:417`

`swap()` snapshots `balance0`/`balance1`, then transfers referral fees out of the pair, but still performs the invariant check and `_update()` using the pre-fee balances. As a result, stored reserves become larger than the contract's actual token balances after any swap that pays a nonzero referral fee.

**Impact:** `getReserves()` and any reserve-based pricing/oracle logic can report balances the pair no longer owns. Until someone calls `sync()`, later `mint()` calls can revert on `balance.sub(reserve)` underflow and `skim()` can revert when subtracting reserves from actual balances, enabling cheap griefing and reserve-dependent integration breakage.

**Paths:**

- Execute any swap large enough that `amount0In.mul(3)/1994` or `amount1In.mul(3)/1994` is nonzero.

- `swap()` reads `balance0`/`balance1`, transfers `refFee` to `referralProgram`, then validates and stores reserves using the stale pre-transfer balances.

- Subsequent reserve consumers observe inflated reserves, and `mint()`/`skim()` can revert until `sync()` is called.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-003: Referral rewards are attributed to a caller-controlled `to` address, enabling likely self-referral farming

**Confidence:** low | **Locations:** `0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol:375, 0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol:392, 0xa0ff0e694275023f4986dc3ca12a6eb5d6056c62/Contract.sol:398`

When referral fees are recorded, the pair credits them to the swap's `to` address, but `to` is fully chosen by the caller and is not authenticated as a real referrer. If the referral program treats `recipient` as the beneficiary of claimable rewards, traders can self-assign those rewards.

**Impact:** If `recordFee()` accrues withdrawable referral rewards for the provided recipient, any trader can route swaps to an address they control and capture referral incentives that were meant for third-party referrers, leaking value funded from pool assets or protocol fee flow.

**Paths:**

- Call `swap()` with `to` set to an attacker-controlled address.

- The pair transfers the referral fee to `referralProgram` and records that fee for the attacker-chosen `to` address.

- If the referral program later lets that recorded recipient claim or benefit from the fee, the trader self-farms the referral payout.

*Round 1 | Agents: codex_1*

---
