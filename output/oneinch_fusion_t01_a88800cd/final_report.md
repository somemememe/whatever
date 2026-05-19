# Audit Report

**Total findings:** 5

## Critical (1)

### F-001: Universal ERC-1271 approval makes every signature for this contract valid

**Confidence:** high | **Locations:** `FlawVerifier.sol:136, FlawVerifier.sol:340, FlawVerifier.sol:355`

`isValidSignature()` always returns the ERC-1271 magic value and never checks either the digest or the provided signature. Because the forged wrapper and replay orders both set `maker = address(this)`, any external integration that accepts ERC-1271 makers can be tricked into treating arbitrary attacker-supplied signatures as valid authorizations from `FlawVerifier`.

**Impact:** Any assets held by the contract can be spent through signature-gated integrations whenever the contract has granted the relevant allowance or otherwise acts as the maker. In this codebase, that directly removes the authorization barrier on the wrapper/replay orders and can enable full theft of contract-held balances.

**Paths:**

- Fund `FlawVerifier` with a token it has approved to a signature-gated protocol -> craft an order with `maker = address(this)` -> supply arbitrary bytes as the signature -> the protocol accepts it because `isValidSignature()` always succeeds -> the protocol pulls the contract's assets.

*Round 1 | Agents: codex*

---

## High (2)

### F-002: Permissionless entrypoint submits a hardcoded replay/theft payload against a historical victim

**Confidence:** high | **Locations:** `FlawVerifier.sol:96, FlawVerifier.sol:102, FlawVerifier.sol:106, FlawVerifier.sol:165, FlawVerifier.sol:168, FlawVerifier.sol:177, FlawVerifier.sol:292, FlawVerifier.sol:300, FlawVerifier.sol:305`

`executeOnOpportunity()` is completely public. On its first call it builds a forged settlement payload that hardcodes `HISTORICAL_VICTIM` and `AMOUNT_TO_STEAL`, then forwards that payload to the settlement contract and, on failure, to the historical relay contract.

**Impact:** Any external caller can trigger the replay attempt and use this contract's balances to do so, without operator consent. If the targeted settlement path is still exploitable or recreated under similar conditions, the call can exfiltrate victim funds into this contract; even when it fails, it still consumes the contract's one-shot execution path and can spend setup capital.

**Paths:**

- Any account calls `executeOnOpportunity()` -> `_prepareMakerCapital()` optionally seeds USDT and `_tryReplayCalldataCorruption()` builds the forged payload -> `_buildTerminalCorruptedInteraction()` embeds `HISTORICAL_VICTIM` and `AMOUNT_TO_STEAL` -> the contract submits the payload to `SETTLEMENT` and then `HISTORICAL_ATTACK_CONTRACT`.

*Round 1 | Agents: codex*

---

### F-004: Unlimited USDT approval to the limit-order protocol leaves a persistent drain surface

**Confidence:** high | **Locations:** `FlawVerifier.sol:144, FlawVerifier.sol:157`

`_prepareMakerCapital()` grants `LIMIT_ORDER_PROTOCOL` a `type(uint256).max` allowance over this contract's USDT and never revokes or scopes that approval to a single transaction.

**Impact:** Any USDT later held by the contract remains exposed indefinitely to the external protocol. In combination with the contract's unconditional ERC-1271 signature acceptance, an attacker can forge maker intent and drain the entire USDT balance whenever the protocol attempts a fill against this contract.

**Paths:**

- First call to `executeOnOpportunity()` -> `_prepareMakerCapital()` sets an infinite USDT allowance for `LIMIT_ORDER_PROTOCOL` -> the contract later receives USDT -> an attacker submits a forged maker order using `FlawVerifier` as maker -> the protocol spends the approved USDT from the contract.

*Round 1 | Agents: codex*

---

## Medium (2)

### F-003: Resolver callback blindly approves any settlement-triggered context

**Confidence:** medium | **Locations:** `FlawVerifier.sol:140, FlawVerifier.sol:141`

`resolveOrders()` only checks that `msg.sender` equals the hardcoded settlement address and ignores the `resolver`, `tokensAndAmounts`, and `data` arguments entirely. As a result, any callback originating from that settlement contract is accepted regardless of which order set, token amounts, or resolver context was intended.

**Impact:** If the settlement system treats a successful resolver callback as authorization to continue a fill, attackers can reuse `FlawVerifier` as a universal resolver for arbitrary settlement flows involving this contract's approvals or maker role. This weakens contextual authorization and compounds the unconditional ERC-1271 signer behavior.

**Paths:**

- An attacker constructs a settlement flow that names `FlawVerifier` as the resolver -> the settlement contract calls `resolveOrders()` with attacker-chosen calldata -> the callback succeeds because only `msg.sender` is checked -> the settlement continues using this contract as an approved resolver/maker context.

*Round 1 | Agents: codex*

---

### F-005: First-caller latch permanently bricks the contract's only active workflow

**Confidence:** high | **Locations:** `FlawVerifier.sol:96, FlawVerifier.sol:97, FlawVerifier.sol:102`

The first arbitrary caller of `executeOnOpportunity()` irreversibly sets `_executed = true`. Every later call skips `_prepareMakerCapital()` and `_tryReplayCalldataCorruption()` and only recomputes profit, even if the first execution happened before funding or failed partway through.

**Impact:** A front-runner can permanently disable the contract's intended one-shot setup and execution path by calling the function before the operator is ready, or by triggering it under conditions that cause the replay attempt to fail. This is a cheap permissionless denial of service against the contract's only meaningful operation.

**Paths:**

- The contract is deployed but not yet funded or conditions are not yet met -> an attacker calls `executeOnOpportunity()` first -> `_executed` becomes `true` before a successful run is achieved -> all future calls return after `_refreshProfit()` and the setup/replay logic can never run again.

*Round 1 | Agents: codex*

---
