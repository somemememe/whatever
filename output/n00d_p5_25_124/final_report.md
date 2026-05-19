# Audit Report

**Total findings:** 3

## High (2)

### F-001: Deployment can embed global operators with authority to move or burn every holder's tokens

**Confidence:** low | **Locations:** `onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol:808, onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol:815, onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol:908, onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol:957, onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol:973, onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol:1302`

`n00dToken` forwards an arbitrary constructor-supplied `defaultOperators` array into OpenZeppelin ERC777. Any address in that array is treated by `isOperatorFor()` as authorized for every holder until each holder individually revokes it, which in turn lets the operator call `operatorSend()` or `operatorBurn()` against all balances. The code supports a protocol-wide drain/burn backdoor if deployment used a non-empty operator list, although the local artifacts do not expose the actual constructor arguments for this deployed instance.

**Impact:** If the deployed instance was initialized with a malicious or later-compromised default operator, that operator can unilaterally transfer tokens out of every user wallet or irreversibly burn user balances without per-user approval.

**Paths:**

- Deploy `n00dToken` with a non-empty `defaultOperators` array controlled by the deployer or another privileged party.

- Victims receive `n00d` and do not explicitly call `revokeOperator()` for that operator.

- The default operator calls `operatorSend(victim, attacker, amount, ...)` to steal funds or `operatorBurn(victim, amount, ...)` to destroy them.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-002: ERC20-looking transfers still execute ERC777 recipient hooks, enabling callback reentrancy in integrators

**Confidence:** high | **Locations:** `onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol:891, onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol:1020, onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol:1108, onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol:1123, onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol:1242`

Both ERC20 entrypoints, `transfer()` and `transferFrom()`, route through `_send(..., false)`. Although `false` disables the mandatory recipient-ack check, `_send()` still invokes `_callTokensReceived()` after crediting the recipient, so a recipient contract registered in ERC1820 can reenter downstream protocols even when they believe they are interacting with a callback-free ERC20 token.

**Impact:** Any vault, AMM, staking contract, bridge, router, or lending market that treats `n00d` as a plain ERC20 can be reentered in the middle of deposit/withdraw/swap flows, leading to double-withdrawals, stale-accounting exploits, or fund theft. The local `FlawVerifier` demonstrates this exact pattern against a toy vault.

**Paths:**

- An integrating protocol calls `transfer()` or `transferFrom()` on `n00d` during a state-changing flow and assumes the token transfer has no callback.

- The attacker-controlled recipient contract registers an `ERC777TokensRecipient` hook in ERC1820.

- `_send()` credits the recipient, then `tokensReceived()` reenters the still-in-progress protocol before its internal accounting/effects are finalized.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-003: Sender-side ERC777 hooks run before balances are debited, exposing pull and burn flows to pre-state reentrancy

**Confidence:** medium | **Locations:** `onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol:1108, onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol:1121, onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol:1135, onchain_auto/0x2321537fd8ef4644bacdceec54e5f35bf44311fa/Contract.sol:1216`

Both `_send()` and `_burn()` call `_callTokensToSend()` before reducing `from`'s balance. A sender-controlled contract that registers an `ERC777TokensSender` hook therefore receives a reentrant callback while its token balance still reflects the pre-transfer/pre-burn amount.

**Impact:** Protocols that pull `n00d` with `transferFrom()` or burn it as part of share accounting, debt repayment, liquidation, or redemption logic can be reentered before the attacker's token balance decreases, enabling stale-balance and duplicate-action exploits in integrations that rely on the pull/burn being atomic from the caller's perspective.

**Paths:**

- The attacker holds `n00d` in a contract that registers an `ERC777TokensSender` hook.

- A downstream protocol calls `transferFrom()`, `send()`, `operatorSend()`, `burn()`, or `operatorBurn()` against that attacker-controlled sender.

- Before `_balances[from]` is decremented, `tokensToSend()` reenters the protocol and exploits logic that still sees the attacker's old token balance or pre-burn state.

*Round 1 | Agents: codex_1*

---
