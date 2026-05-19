# Audit Report

**Total findings:** 6

## High (3)

### F-001: Signed orders can be replayed and overfilled indefinitely

**Confidence:** high | **Locations:** `0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:487, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:613`

`fillOrder` records `sFilledFraction[orderHash]` after execution but never checks whether the order was already filled or whether `sFilledFraction[orderHash] + fraction` exceeds `1e18`. Because partial fills are disabled and only `fraction == 1e18` is accepted, the same signed order can be executed repeatedly until the maker's balances or allowances run out.

**Impact:** A taker can reuse a single signature to force the maker through the same trade multiple times, draining additional upfront tokens and minting far more long/short exposure than the maker authorized.

**Paths:**

- Maker signs one order intended for a single fill.

- Taker calls `fillOrder(order, signature, 1e18)` once.

- The contract performs transfers and minting, then sets `sFilledFraction[orderHash] = 1e18`.

- Because no pre-check uses `sFilledFraction`, the taker calls the same order again with the same inputs.

- Each replay repeats the same asset transfers and fresh long/short minting.

*Round 1 | Agents: codex*

---

### F-002: Settlement can be manipulated by delaying start and end snapshots away from the target window

**Confidence:** high | **Locations:** `0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/interfaces/ISilicaPools.sol:193, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:396, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:409, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:442, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:456, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:856, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:874`

The interface requires end-state accounting to be pro-rated back to the target time range, but the implementation simply snapshots `index.balance()` and `index.shares()` at the actual `startPool`/`endPool` call times and uses those raw values directly. Since anyone may call these functions any time after the target timestamps, economically interested actors can choose favorable delayed snapshot times.

**Impact:** An attacker can exclude unfavorable early performance, include favorable post-target performance, or otherwise bias settlement toward their long or short position, materially redistributing pool collateral and potentially flipping the winning side.

**Paths:**

- A pool reaches `targetStartTimestamp`, but nobody starts it immediately.

- An attacker first acquires the side that benefits from excluding the early portion of the target window.

- The attacker calls `startPool` late, fixing `indexInitialBalance` and `indexShares` at a favorable time.

- After `targetEndTimestamp`, the attacker similarly delays `endPool` until `index.balance()` is favorable.

- Redemption uses the delayed raw snapshots instead of a pro-rated target-window result.

*Round 1 | Agents: codex*

---

### F-003: Pools on decreasing indices can become permanently unendable

**Confidence:** high | **Locations:** `0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/interfaces/ISilicaIndex.sol:69, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/libraries/PoolMaths.sol:87, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/libraries/PoolMaths.sol:89, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:454`

`ISilicaIndex` explicitly states that `balance()` is not required to increase over time, but `PoolMaths.grossBalanceChangePerShare` reverts unless `indexBalance >= indexInitialBalance`. Because `endPool` always routes through this function, any pool whose tracked index balance falls during the term can never be finalized, even though the pool math is supposed to clamp outcomes at `floor`.

**Impact:** If the tracked index decreases, `endPool` can revert forever, leaving `actualEndTimestamp` unset and preventing both long and short holders from redeeming. Pool collateral remains effectively trapped.

**Paths:**

- A pool starts and records `indexInitialBalance`.

- The index balance falls before maturity.

- Any caller tries to execute `endPool` after `targetEndTimestamp`.

- `grossBalanceChangePerShare` reverts on `indexBalance < indexInitialBalance`, so `actualEndTimestamp` is never set.

- `redeemLong` and `redeemShort` remain blocked by the pool-not-ended check.

*Round 1 | Agents: codex*

---

## Medium (3)

### F-004: Deflationary or negative-rebasing payout tokens can undercollateralize pools

**Confidence:** medium | **Locations:** `0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:824, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:826, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:828, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:904`

`_collateralizedMint` increases `sState.collateralMinted` by the nominal collateral amount and assumes `safeTransferFrom` delivers that exact amount. If the chosen `payoutToken` charges transfer fees, burns on transfer, or later rebases downward, the contract's actual token balance can fall below `collateralMinted` with no corrective accounting.

**Impact:** Pools can appear fully collateralized while holding fewer payout tokens than their accounting assumes. Later refunds, bounty payouts, or redemptions can fail or leave remaining claimants underpaid because the pool is insolvent.

**Paths:**

- A pool is created using a payout token with transfer fees or negative rebases.

- A mint or order fill transfers `collateral`, but the contract receives less than the recorded nominal amount, or later loses balance through rebasing.

- `sState.collateralMinted` still tracks the higher amount.

- Subsequent `collateralRefund`, bounty, `redeemLong`, or `redeemShort` calls rely on inflated accounting and eventually exceed the real token balance.

*Round 1 | Agents: codex*

---

### F-005: Orders remain fillable after pool start or even after maturity until explicit finalization

**Confidence:** medium | **Locations:** `0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:487, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:509, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:512`

`fillOrder` only blocks orders whose referenced pools have already been finalized (`actualEndTimestamp != 0`). It does not prevent fills after `targetStartTimestamp`, after `startPool`, or even after `targetEndTimestamp` so long as nobody has called `endPool` yet. As a result, signed orders remain executable after much or all of the payoff path is already known.

**Impact:** Takers can selectively execute stale maker orders only when the revealed index path is favorable, extracting value from makers at obsolete terms with sharply reduced market risk.

**Paths:**

- A maker signs an order with an expiry that extends past pool start or maturity.

- The target window progresses and the pool outcome becomes partly or fully knowable.

- No one has finalized the pool yet, so `actualEndTimestamp` is still zero.

- An informed taker fills the stale order after observing favorable market information.

- The taker receives exposure priced on stale assumptions while the maker is forced into the unfavorable side.

*Round 1 | Agents: codex*

---

### F-006: Emergency pause only blocks order filling, not direct minting or pool lifecycle actions

**Confidence:** high | **Locations:** `0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:138, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:162, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:396, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:442, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:487, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:661, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:686, 0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:710`

The owner-facing API describes `pause()` as pausing the protocol, but the `paused` flag is enforced only inside `fillOrder`. Direct minting (`collateralizedMint`), pool start/end, refunds, and redemptions all remain callable while the protocol is paused.

**Impact:** During an incident, the owner cannot fully freeze protocol state changes. Attackers can bypass the pause and continue minting or moving pools through lifecycle transitions, limiting the usefulness of the emergency control when it is most needed.

**Paths:**

- The owner calls `pause()` expecting to halt the protocol.

- An attacker or user calls `collateralizedMint`, `startPool`, `endPool`, `collateralRefund`, `redeemLong`, or `redeemShort` directly.

- Those calls succeed because none of those entry points check `paused`.

- The protocol continues changing state despite being paused.

*Round 1 | Agents: codex*

---
