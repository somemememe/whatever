# Audit Report

**Total findings:** 5

## High (1)

### F-001: Permissionless fee liquidation uses `amountOutMin = 0`, enabling MEV to drain protocol fee value

**Confidence:** high | **Locations:** `0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/DecentralizedIndex.sol:89-125`

Any non-pool token transfer can trigger `_feeSwap`, and `_feeSwap` sells accumulated index-fee inventory through the V2 router with `amountOutMin` hardcoded to `0`. Because the trigger is public and the sale has no price protection, a searcher can move the IDX/DAI pool immediately before the swap and force the contract to dump fee inventory at an arbitrarily bad spot price.

**Impact:** Protocol fee inventory can be systematically siphoned away from LP stakers and token holders into MEV profit. The larger the accumulated fee balance, the larger the extractable loss.

**Paths:**

- Accumulate fee tokens in the index contract via normal bond/debond activity.

- Front-run by pushing the IDX/DAI V2 price against the contract.

- Trigger any qualifying transfer from a non-pool address so `_feeSwap` executes.

- Back-run to unwind the manipulation and capture the value the contract lost on the forced sale.

*Round 1 | Agents: codex_1*

---

## Medium (3)

### F-002: Public reward conversion can be sandwiched to siphon pending DAI rewards

**Confidence:** medium | **Locations:** `0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/TokenRewards.sol:107-161, 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/DecentralizedIndex.sol:122-125`

`depositFromDAI` is permissionless and swaps the rewards contract's entire DAI balance into the rewards token in one trade. The function therefore lets any caller choose the execution moment for converting all pending rewards, and the swap only enforces a slippage-discounted minimum output derived from TWAP. A searcher can sandwich this conversion by worsening the DAI->rewards spot price just enough to stay within the allowed slippage, then unwind after the contract overpays.

**Impact:** Pending DAI earmarked for stakers can be converted into materially fewer reward tokens, transferring reward value from stakers to MEV traders whenever a large DAI balance is waiting to be converted.

**Paths:**

- Wait until the rewards contract has accumulated DAI from flash fees or `_feeSwap`.

- Front-run by buying the rewards token in the V3 pool to worsen the DAI->rewards execution price.

- Call `depositFromDAI(0)` or trigger `_feeSwap` so the contract converts the full pending DAI balance at the manipulated price.

- Back-run by selling the rewards tokens bought in the front-run and keeping the slippage extracted from the contract swap.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-003: Unbounded slippage escalation can permanently brick reward conversions

**Confidence:** medium | **Locations:** `0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/TokenRewards.sol:38, 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/TokenRewards.sol:140-160`

Every failed `exactInputSingle` increments `_rewardsSwapSlippage` by 10, there is no cap, and the contract is compiled under Solidity 0.7 without checked arithmetic. Once `_rewardsSwapSlippage` exceeds 1000, `1000 - _rewardsSwapSlippage` underflows when computing `amountOutMinimum`, producing an unattainable minimum output for normal `_amountOut` values. From that point onward, every conversion attempt falls back into the `catch` branch and the counter is never reset.

**Impact:** DAI sent to the rewards contract can become permanently stuck and future reward distributions can halt, causing lasting lockup of protocol fee revenue intended for stakers.

**Paths:**

- Cause `depositFromDAI` swaps to fail repeatedly, for example by manipulating execution conditions so `exactInputSingle` reverts while the outer function survives via `catch`.

- Repeat until `_rewardsSwapSlippage` is pushed above 1000.

- Subsequent `depositFromDAI` calls compute an underflowed `amountOutMinimum` and keep failing forever, leaving DAI trapped in the rewards contract.

*Round 1 | Agents: codex_1*

---

### F-004: Per-asset rounding in `bond` can mint undercollateralized index supply

**Confidence:** low | **Locations:** `0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/WeightedIndex.sol:117-136, 0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/WeightedIndex.sol:153-159`

`bond` computes the minted index amount from the chosen input token once, but it floors each required constituent transfer independently inside the loop. For some weight/decimal combinations, an attacker can split a larger bond into many small tranches where one or more companion assets round down to zero while the minted index amount remains positive. The accumulated index tokens can later be debonded pro rata against the fully backed pool.

**Impact:** If the deployed basket contains practical dust thresholds, an attacker can gradually mint underbacked index tokens and eventually redeem more of the rounded-down assets than were ever deposited, diluting honest holders and extracting real basket value.

**Paths:**

- Choose a bonding asset and tranche size such that the attacker still mints a positive amount of index tokens but one or more other constituent transfers floor to zero.

- Repeat many small `bond` calls to omit those rounded-down assets repeatedly.

- Debond the accumulated index tokens to withdraw a pro-rata share of all basket assets, including assets that were systematically under-supplied during bonding.

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-005: Anyone can sweep stray ETH and unsupported ERC20s to an external owner address

**Confidence:** high | **Locations:** `0xdbb20a979a92cccce15229e41c9b082d5b5d7e31/contracts/DecentralizedIndex.sol:254-279`

`rescueERC20` and `rescueETH` are entirely permissionless. Any caller can force the contract to send all non-index ERC20 balances or ETH to `Ownable(address(V3_TWAP_UTILS)).owner()`, which is an external address unrelated to the original sender. The `receive()` hook also auto-forwards any ETH sent to the contract to that same owner.

**Impact:** Accidental transfers, airdrops, and other unsupported balances can be irreversibly redirected away from users or expected protocol custody by any third party. This is a real loss channel for stray funds, even though indexed assets themselves are excluded.

**Paths:**

- A user or external contract sends ETH or a non-index ERC20 to the index contract.

- Any third party calls `rescueETH()` or `rescueERC20(token)`.

- The full balance is transferred to the owner of `V3_TWAP_UTILS`, not back to the sender or to a protocol-governed recovery path.

*Round 1 | Agents: codex_1, opencode_1*

---
