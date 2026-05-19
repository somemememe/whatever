# Audit Report

**Total findings:** 4

## Critical (4)

### F-001: Settlement executes caller-supplied interaction bytes that are not bound to the signed order payload

**Confidence:** high | **Locations:** `FlawVerifier.sol:201, FlawVerifier.sol:223, FlawVerifier.sol:263, FlawVerifier.sol:273, FlawVerifier.sol:336, FlawVerifier.sol:345`

The PoC constructs orders whose in-struct `interactions` field is empty or dummy (`hex""` / `hex"0000000000"`), then supplies the real execution logic through the separate `interaction` argument passed into settlement. Because those externally supplied bytes drive nested settlement and resolver execution despite not matching the order's own `interactions` field, the settlement path appears to execute materially different callbacks than the order payload itself commits to.

**Impact:** An attacker can attach arbitrary callbacks or resolver logic to an otherwise valid order, breaking signature binding and enabling unauthorized execution paths that can move maker or settlement-held assets.

**Paths:**

- `executeOnOpportunity()` -> `_tryReplayCalldataCorruption()` -> `_buildReplayOrder(... interactions: hex"")` -> attacker-controlled external `interaction` chain -> `settleOrders`

- `executeOnOpportunity()` -> `_drainSettlementToken()` -> order uses dummy `interactions` -> separate resolver `interaction` passed to `settleOrders`

*Round 1 | Agents: codex*

---

### F-002: Self-targeted settlement interactions allow reentrancy that satisfies `allowedSender = SETTLEMENT`

**Confidence:** high | **Locations:** `FlawVerifier.sol:197, FlawVerifier.sol:216, FlawVerifier.sol:223, FlawVerifier.sol:243, FlawVerifier.sol:257, FlawVerifier.sol:264, FlawVerifier.sol:304`

The replay chain repeatedly targets `SETTLEMENT` from within settlement interactions while every forged replay order sets `allowedSender` to `SETTLEMENT`. This only succeeds if settlement can call back into itself and the nested call observes `msg.sender == SETTLEMENT`, allowing externally initiated execution of orders that were intended to be invokable only by the settlement contract itself.

**Impact:** Arbitrary users can trigger private or restricted orders by wrapping them inside self-calls, bypassing `allowedSender` protections and enabling theft of victim funds or other unauthorized fills.

**Paths:**

- `executeOnOpportunity()` -> `_tryReplayCalldataCorruption()` -> `interaction5` targets `SETTLEMENT`

- outer `settleOrders` -> nested self-call into settlement -> replay orders with `allowedSender = SETTLEMENT` execute

*Round 1 | Agents: codex*

---

### F-003: Unchecked dynamic offset and length parsing enables calldata corruption and replay of historical orders

**Confidence:** high | **Locations:** `FlawVerifier.sol:183, FlawVerifier.sol:184, FlawVerifier.sol:186, FlawVerifier.sol:223, FlawVerifier.sol:235, FlawVerifier.sol:236, FlawVerifier.sol:280`

The PoC forges dynamic-field metadata using attacker-chosen signature/interaction offsets and an almost-`uint256.max` interaction length, then appends a crafted suffix interpreted as trusted order data for a historical victim. This indicates the settlement decoder does not safely bound-check dynamic offsets and lengths before parsing nested order calldata, permitting wraparound/corruption of decode boundaries.

**Impact:** Attackers can splice attacker-controlled bytes into later decoded fields, replay historical victim orders, or forge unauthorized fills without possessing a valid fresh authorization from the victim.

**Paths:**

- `executeOnOpportunity()` -> `_tryReplayCalldataCorruption()` -> forged `fakeSignatureLengthOffset` / `fakeInteractionLengthOffset` / `fakeInteractionLength`

- crafted nested payload -> settlement decodes corrupted order bytes -> historical victim USDC order is replayed via `HISTORICAL_ATTACK_CONTRACT` or direct `SETTLEMENT` call

*Round 1 | Agents: codex*

---

### F-004: Settlement releases real taker assets when a malicious maker token lies about transfers and balances

**Confidence:** high | **Locations:** `FlawVerifier.sol:323, FlawVerifier.sol:326, FlawVerifier.sol:333, FlawVerifier.sol:345, FlawVerifier.sol:356, FlawVerifier.sol:501, FlawVerifier.sol:506, FlawVerifier.sol:510`

The drain path creates orders whose `makerAsset` is `FakeMakerToken`, a token that always returns success for `transfer`/`transferFrom`/`approve` and reports an effectively infinite `balanceOf`. The PoC then asks settlement to pay out each real token balance it holds. This supports that settlement credits incoming maker assets based on ERC20 call success or reported balances instead of verifying actual balance deltas.

**Impact:** Any real ERC20 inventory held by the settlement contract can be swapped out for a worthless fake token, allowing attackers to drain pooled or stranded balances across multiple assets.

**Paths:**

- `executeOnOpportunity()` -> loop over target tokens -> `_drainSettlementToken(takerAsset, maker, FakeMakerToken, resolver, ...)`

- settlement attempts to pull fake maker asset -> fake ERC20 reports success / huge balance -> settlement releases real `takerAsset` balance to attacker

*Round 1 | Agents: codex*

---
