# Audit Report

**Total findings:** 11

## Medium (4)

### F-002: collect() and collectLimOrder() erase unpaid claims instead of reverting on shortfalls

**Confidence:** high | **Locations:** `liquidity.sol:460, liquidity.sol:461, liquidity.sol:463, liquidity.sol:464, limitOrder.sol:392, limitOrder.sol:397, limitOrder.sol:399, limitOrder.sol:400, iZiSwapPool.sol:320, iZiSwapPool.sol:321`

Both collection paths decrement the user's stored claim before checking how many tokens the pool can actually pay, then clamp the transfer to the current balance. In `collectLimOrder()`, the module still returns and emits the pre-clamp amounts, so callers can be told they collected more than was actually transferred.

**Impact:** If the pool is ever underfunded, the first claimer permanently loses the unpaid remainder instead of reverting and preserving the claim. Limit-order integrations can also overcredit users because the returned and emitted amounts may exceed the tokens actually sent.

**Paths:**

- The pool becomes short of token balances for any reason, such as rebasing tokens, asset loss, or prior misaccounted payouts.

- A user calls `collect()` or `collectLimOrder()` for the full amount owed.

- Storage is reduced immediately, only `min(claim, balance)` is transferred, and the unpaid remainder is irretrievably burned.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-006: Permissionless pool creation lets attackers permanently squat pair/fee slots and choose the initial price

**Confidence:** high | **Locations:** `iZiSwapFactory.sol:95, iZiSwapFactory.sol:101, iZiSwapFactory.sol:105, iZiSwapFactory.sol:110, iZiSwapPool.sol:128, iZiSwapPool.sol:149`

`newPool()` is permissionless, only rejects identical token addresses, and uses a CREATE2 salt keyed solely by `(tokenX, tokenY, fee)`. Because the factory never checks that either token is an already deployed contract and the salt omits `currentPoint`, any third party can deploy the sole canonical pool for that tuple first with arbitrary staged parameters, while the pool constructor blindly accepts the staged `currentPoint`.

**Impact:** Pair launches can be front-run or pre-squatted before token deployment. The intended deployer cannot recreate the canonical pool with the desired initialization, and downstream users or integrators may be pushed onto an attacker-chosen starting price or forced to use a different fee tier.

**Paths:**

- Front-run a pending `newPool(tokenA, tokenB, fee, fairPoint)` transaction with `newPool(tokenA, tokenB, fee, hostilePoint)`.

- Pre-create pools for predictable future token addresses and chosen fee tiers before the real token contracts go live.

*Round 2 | Agents: codex_1*

---

### F-007: Same-point limit orders settle by first claim rather than order time

**Confidence:** high | **Locations:** `libraries/UserEarn.sol:38, libraries/UserEarn.sol:46, libraries/UserEarn.sol:60, limitOrder.sol:166, limitOrder.sol:177, limitOrder.sol:194, limitOrder.sol:205`

Per-user settlement at a point follows the documented `first claim first earn` rule. `updateUnlegacyOrder()` and `updateLegacyOrder()` draw from shared point-level `earn` or `legacyEarn`, and `decLimOrderWithX/Y()` allow `delta = 0`, so any owner at that point can update after a shared fill without cancelling size. The first updater consumes as much of the shared proceeds as their own remaining order allows, regardless of placement order.

**Impact:** A later order owner at the same point and in the same direction can race older orders and capture fills that many limit-order users would expect to settle FIFO. Passive same-price orders are therefore MEV-stealable unless owners actively update after fills.

**Paths:**

- Victim and attacker both rest same-direction orders at point `P`; a swap partially fills the aggregate point order; attacker immediately calls `decLimOrderWithX(P,0)` or `decLimOrderWithY(P,0)` first; victim updates later and finds the shared proceeds depleted.

- The same race exists after a full clear through the legacy path because `updateLegacyOrder(0, ...)` also assigns shared `legacyEarn` to the first updater.

*Round 2 | Agents: codex_1*

---

### F-010: Zero-liquidity gaps let attackers move the oracle-reported price at little or no trading cost

**Confidence:** medium | **Locations:** `swapX2Y.sol:258, swapX2Y.sol:438, swapY2X.sol:209, swapY2X.sol:367, iZiSwapPool.sol:458, libraries/Oracle.sol:170, libraries/Oracle.sol:200`

In both swap directions, including the desire-based variants, the pool jumps `state.currentPoint` straight to the next initialized point or boundary whenever `st.liquidity == 0`, without consuming trader input for the skipped range. `observe()` then derives current cumulative oracle values from `state.currentPoint` whenever the queried timestamp is after the last stored observation, so any time spent after the jump is counted at the jumped-to price even though traversing the empty gap cost nothing.

**Impact:** Sparse-liquidity pools can have their spot point and TWAP shifted much more cheaply than the apparent point distance suggests. Downstream integrations that treat `observe()` as a robust price oracle can therefore be manipulated after an attacker pushes the pool into an empty gap or through one.

**Paths:**

- Move the pool into or next to a gap with no active liquidity.

- Execute a small swap that free-jumps across the empty range and only pays once it reaches the next active price or boundary.

- Leave the pool at that jumped-to point for the desired interval, then let a TWAP consumer read `observe()`.

*Round 3 | Agents: codex_1*

---

## Low (6)

### F-001: Output transfers silently underdeliver with fee-on-transfer or deceptive ERC20s

**Confidence:** high | **Locations:** `libraries/TokenTransfer.sol:13, swapX2Y.sol:326, swapY2X.sol:292, liquidity.sol:466, liquidity.sol:469, limitOrder.sol:402, limitOrder.sol:405, flash.sol:142, flash.sol:143, iZiSwapPool.sol:526, iZiSwapPool.sol:527`

All outbound token transfers only require `transfer()` to return success (or no returndata). The pool never verifies that the recipient actually received the nominal amount, so fee-on-transfer, rebasing-on-transfer, or otherwise deceptive tokens can pay out less than the amount the pool just finalized in state.

**Impact:** Traders, LPs, limit-order users, flash borrowers, and the protocol fee receiver can receive less than the quoted or owed amount whenever a listed token skims or suppresses outbound transfers. The protocol has no on-chain signal that the payout was short.

**Paths:**

- Create or list a pool whose token charges transfer fees or otherwise underdelivers on outbound `transfer()`.

- Trigger a swap, collect, flash loan, or protocol-fee withdrawal that pays that token out.

- The transfer call succeeds, state is finalized, but the recipient receives fewer tokens than the nominal payout.

*Round 1 | Agents: codex_1*

---

### F-003: enableFeeAmount() allows fee-tier parameters that disable core pool functionality

**Confidence:** high | **Locations:** `iZiSwapFactory.sol:88, iZiSwapFactory.sol:91, iZiSwapFactory.sol:106, iZiSwapPool.sol:119, liquidity.sol:336, swapX2Y.sol:151, swapX2Y.sol:166, swapX2Y.sol:370, swapY2X.sol:150, swapY2X.sol:166, swapY2X.sol:334`

The factory only checks `pointDelta > 0` and never bounds `fee` or `pointDelta`. A tier with `fee >= 1_000_000` makes swap math hit `1e6 - fee` as zero or underflow, reverting every swap. A tier with `pointDelta > 800000` collapses the usable price grid to a single point, so `mint()` can never satisfy `leftPt < rightPt` within the pool's allowed range.

**Impact:** The owner can accidentally or deliberately register tiers that let users create pools with broken core functionality: some tiers cannot execute swaps at all, while others cannot accept LP liquidity.

**Paths:**

- Owner calls `enableFeeAmount()` with an out-of-range `fee` or `pointDelta`.

- A user creates a pool under that tier.

- Either swaps revert immediately (`fee >= 1_000_000`) or no valid liquidity range can ever be minted (`pointDelta > 800000`).

*Round 1 | Agents: codex_1, opencode_1*

---

### F-004: Unbounded defaultFeeChargePercent can make newly created pools revert on fee distribution

**Confidence:** high | **Locations:** `iZiSwapFactory.sol:79, iZiSwapFactory.sol:118, iZiSwapFactory.sol:134, swapX2Y.sol:225, swapX2Y.sol:288, swapX2Y.sol:408, swapX2Y.sol:452, swapY2X.sol:248, swapY2X.sol:389, flash.sol:156`

The factory constructor and `modifyDefaultFeeChargePercent()` accept values above 100, and `newPool()` copies that value directly into each pool. When a liquidity-backed swap or flash later computes `feeAmount - chargedFeeAmount`, any inherited `feeChargePercent > 100` makes the subtraction underflow and revert.

**Impact:** New pools can be deployed with a latent configuration bug that prevents normal fee-bearing trading or flash loans until the owner separately fixes each pool's `feeChargePercent`.

**Paths:**

- Owner sets `defaultFeeChargePercent` above 100.

- A user creates a new pool after the bad default is in place.

- The first swap path or flash loan that tries to distribute liquidity fees reverts on `feeAmount - chargedFeeAmount`.

*Round 1 | Agents: codex_1*

---

### F-005: test/TestAddLimOrder.payCallback() lets arbitrary callers pull approved tokens from the encoded payer

**Confidence:** high | **Locations:** `test/TestAddLimOrder.sol:29, test/TestAddLimOrder.sol:34, test/TestAddLimOrder.sol:36, test/TestAddLimOrder.sol:39`

`payCallback()` never verifies that `msg.sender` is the expected iZiSwap pool. Any caller can supply callback data with a victim as `payer` and use this helper to execute `transferFrom()` from that victim to itself.

**Impact:** If this test helper is ever deployed outside an isolated test environment and users approve it, an attacker can directly steal the approved token balances.

**Paths:**

- The `TestAddLimOrder` helper is deployed and a user grants it ERC20 allowance.

- An attacker calls `payCallback()` directly with calldata encoding that user as `payer`.

- The helper transfers the victim's approved tokens to the attacker's address (`msg.sender`).

*Round 1 | Agents: codex_1*

---

### F-008: Crossing resting limit orders via addLimOrder bypasses swap fee accounting

**Confidence:** medium | **Locations:** `limitOrder.sol:229, limitOrder.sol:253, limitOrder.sol:257, limitOrder.sol:276, limitOrder.sol:301, limitOrder.sol:306, limitOrder.sol:330, limitOrder.sol:334, limitOrder.sol:353, limitOrder.sol:379, swapX2Y.sol:151, swapX2Y.sol:161, swapY2X.sol:150, swapY2X.sol:161`

`addLimOrderWithX/Y()` immediately match against opposite resting point orders and credit the taker through `earnAssign`, but the callback only requests the matched principal plus any residual order amount. Unlike the swap paths that consume the same point orders, these branches never compute `feeAmount`, `chargedFeeAmount`, or update LP fee scales for the matched portion.

**Impact:** Whenever resting opposite orders exist, a taker can route through `addLimOrder` plus `collectLimOrder` instead of `swap` and pay no pool fee or protocol charge on that matched flow. Fee capture becomes optional for order-to-order crossing, creating inconsistent execution economics.

**Paths:**

- If opposite resting orders exist at `currentPoint`, call `addLimOrderWithX()` or `addLimOrderWithY()` there with just enough input to consume them, then withdraw the acquired token with `collectLimOrder()`.

- Repeat the same pattern whenever new resting opposite orders appear, using `addLimOrder` as a fee-free taker path instead of the normal swap entrypoint.

*Round 2 | Agents: codex_1*

---

### F-009: Oversized flash-fee accruals can push fee-growth counters to their limit and wedge later accruals

**Confidence:** medium | **Locations:** `flash.sol:133, flash.sol:145, flash.sol:158, flash.sol:163, swapX2Y.sol:228, swapX2Y.sol:291, swapY2X.sol:251, swapY2X.sol:396, libraries/Liquidity.sol:53`

Position accounting explicitly treats `feeScaleX_128` and `feeScaleY_128` as wrapping counters, but fee accrual sites update them with checked `+`. Because `flash()` computes fees from the requested `amountX/amountY` even when the pool lends less, and accepts any callback overpayment as additional paid fees, an attacker can use a tiny-liquidity pool and an enormous flash notional to move a side's fee scale close to `uint256.max`. The next accrual on that side then overflows and reverts instead of wrapping.

**Impact:** After a sufficiently large flash-fee accrual, later swaps or flashes that would accrue fees on the same side can start reverting, effectively DoSing fee-accruing activity for that token side of the pool. The attack is cheapest on very low-liquidity pools and most practical when one token is attacker-controlled and can mint an arbitrarily large supply.

**Paths:**

- Seed or find a pool with very small active liquidity.

- Call `flash()` with a huge `amountX` or `amountY` so the computed fee is enormous even if `actualAmountX/Y` is clipped by the pool balance, and repay that fee in the callback.

- This pushes the corresponding `feeScale*_128` near its numeric limit without reverting.

- Trigger one more fee-accruing swap or flash on the same side and hit checked overflow in the next `feeScale*_128 += ...` update.

*Round 3 | Agents: codex_1, opencode_1*

---

## Informational (1)

### F-012: The public `orderOrEndpoint` getter is keyed by a normalized index, not by the documented point

**Confidence:** high | **Locations:** `iZiSwapPool.sol:82, libraries/OrderOrEndpoint.sol:6, libraries/OrderOrEndpoint.sol:10, interfaces/IiZiSwapPool.sol:432`

Internally, `orderOrEndpoint` state is stored at `point / pointDelta`, but the pool exposes the compiler-generated raw mapping getter while the interface documents the argument as if callers should pass the actual point. On pools with `pointDelta != 1`, callers that query `orderOrEndpoint(realPoint)` read the wrong storage slot unless they manually normalize the key first.

**Impact:** Off-chain tooling and integrations that inspect initialized points or resting-order presence through this getter can silently miss live state, producing incomplete monitoring, bad quotes, or unsafe routing decisions built on incorrect point availability.

**Paths:**

- Query `orderOrEndpoint(realPoint)` on a pool whose `pointDelta` is greater than 1.

- The getter looks up the raw mapping slot instead of the internally normalized index and often returns `0` for an actually initialized point.

- A router, monitor, or analytics system builds decisions from that incorrect result.

*Round 3 | Agents: codex_1*

---
