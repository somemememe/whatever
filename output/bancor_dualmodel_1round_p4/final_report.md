# Audit Report

**Total findings:** 5

## Critical (1)

### F-001: Inherited public token helper functions let any caller move funds as BancorNetwork

**Confidence:** high | **Locations:** `onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:520, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:533, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:547`

`BancorNetwork` inherits `TokenHandler`, whose `safeApprove`, `safeTransfer`, and `safeTransferFrom` helpers are all declared `public` with no access control. Any external caller can therefore invoke ERC20 `approve`, `transfer`, or `transferFrom` from the BancorNetwork contract context itself.

**Impact:** Any account that has approved BancorNetwork can be drained by an arbitrary caller via `safeTransferFrom`. Any ERC20 balance held by BancorNetwork can be stolen via `safeTransfer`, and an attacker can also grant themselves allowance from BancorNetwork via `safeApprove` and then pull funds with `transferFrom`. This is a direct loss-of-funds issue.

**Paths:**

- Attacker calls `safeTransferFrom(token, victim, attacker, amount)` after a victim has approved BancorNetwork for trading.

- Attacker calls `safeTransfer(token, attacker, amount)` to pull any ERC20 balance currently sitting in BancorNetwork.

- Attacker calls `safeApprove(token, attacker, allowance)` and then drains BancorNetwork-held tokens with the token's `transferFrom`.

*Round 1 | Agents: codex_1*

---

## High (2)

### F-002: ETH-consuming conversion steps forward stale `msg.value` instead of the hop amount

**Confidence:** high | **Locations:** `onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1145, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1146, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1190, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1197`

When a v28+ step consumes ETH, `doConversion` always calls `converter.convert.value(msg.value)(...)` instead of forwarding the current hop's `fromAmount`. If the source asset was an EtherToken, `handleSourceToken` first withdraws it into ETH held by BancorNetwork, but the subsequent payable convert call still forwards the original transaction `msg.value` rather than the newly unwrapped amount. The same stale-value mistake applies to later ETH-consuming hops in multi-step routes.

**Impact:** EtherToken-funded routes through newer converters can revert even though BancorNetwork already unwrapped the EtherToken, and later hops that need ETH can also fail because the converter receives the wrong amount of ETH. This creates permissionless denial of service for valid conversion paths and can strand route execution until the contract is fixed.

**Paths:**

- User converts a registered EtherToken into another asset through a v28+ converter; BancorNetwork withdraws the EtherToken to ETH, then forwards `msg.value == 0` instead of the hop amount.

- User executes a multi-hop route with an intermediate ETH hop; the later v28+ converter again receives the transaction's original `msg.value` instead of that hop's `fromAmount` and reverts.

*Round 1 | Agents: codex_1*

---

### F-005: `completeXConversion` never sources the bridged tokens from BancorX

**Confidence:** medium | **Locations:** `onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1090, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1097, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1100, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1193, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1204`

`completeXConversion` reads a claimable amount from `_bancorX.getXTransferAmount(_conversionId, msg.sender)` and then immediately calls `convertByPath`, but `convertByPath`/`handleSourceToken` always source the first-hop tokens from `msg.sender` (or `msg.value`), not from the `_bancorX` contract. Despite the function comment saying the amount is taken from BancorX, the implementation never pulls or claims those bridged tokens.

**Impact:** Cross-chain completion through `completeXConversion` can fail unless the recipient already owns and has approved an equivalent amount of the source token locally. If the recipient does pre-fund the call, BancorNetwork converts the recipient's own tokens while the BancorX-held transfer remains untouched. This breaks the intended cross-chain conversion flow and can leave bridged funds stuck or require users to front additional capital.

**Paths:**

- User receives a cross-chain transfer intended for `completeXConversion`; the function computes the amount from BancorX but `handleSourceToken` still tries to `transferFrom` the user's wallet.

- If the user has not pre-approved and pre-funded the source token, the completion reverts and the cross-chain conversion flow is DOSed.

- If the user does pre-approve enough source tokens, BancorNetwork converts the user's own balance instead of the BancorX-held transfer amount, while the BancorX-side balance remains unconsumed.

*Round 1 | Agents: opencode_1, merge_reviewer*

---

## Medium (2)

### F-003: User-supplied path anchors can redirect source tokens to arbitrary contracts

**Confidence:** low | **Locations:** `onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:959, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:967, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1175, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1204, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1257, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1258`

`convertByPath` only validates path length. It trusts each user-supplied anchor's `owner()` as the converter and never checks that the converter is an approved/active Bancor converter. `handleSourceToken` and `createConversionData` then use that unchecked owner address as the conversion target/spender, so a malicious path can point BancorNetwork at attacker-controlled contracts.

**Impact:** A malicious frontend or path source can trick users who already approved BancorNetwork into transferring source tokens to an attacker-controlled contract or into granting that contract allowance, while still interacting with the canonical router. This is a realistic token-drain primitive even though it depends on malicious path construction rather than a compromised registry.

**Paths:**

- Victim approves BancorNetwork for a token and submits `convertByPath` with a malicious path whose first anchor is attacker-controlled.

- For a 'newer' fake converter, `handleSourceToken` transfers the victim's source tokens directly to the attacker's contract.

- For an 'older' fake converter, BancorNetwork first pulls tokens to itself and then approves the attacker's contract, which can take them during `change` while returning a fake positive amount.

*Round 1 | Agents: codex_1*

---

### F-004: ETH/EtherToken normalization is only applied at path endpoints, breaking internal ETH hops

**Confidence:** medium | **Locations:** `onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:892, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:894, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1288, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1292, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1299, onchain/0x5f58058c0ec971492166763c8c22632b583f667f/Contract.sol:1303`

`rateByPath` normalizes every EtherToken/ETH alias hop to `ETH_RESERVE_ADDRESS`, but `createConversionData` only performs this normalization for `data[0].sourceToken` and `data[last].targetToken`. Internal hops that enter or exit ETH through a registered EtherToken are left with the raw EtherToken address even when the converter version expects the ETH reserve sentinel.

**Impact:** Routes that bridge through ETH/EtherToken in the middle of the path can be quoted as valid but fail during execution because the constructed conversion steps use the wrong token identifiers for newer converters. This causes permissionless denial of service for a class of otherwise valid multi-hop trades.

**Paths:**

- A path such as `tokenA -> EtherToken -> tokenB` is quoted with internal ETH normalization in `rateByPath`, but execution leaves the middle EtherToken hop unnormalized.

- A newer converter that expects `ETH_RESERVE_ADDRESS` for an internal ETH-facing step instead receives the EtherToken contract address and rejects or mishandles the hop.

*Round 1 | Agents: codex_1*

---
