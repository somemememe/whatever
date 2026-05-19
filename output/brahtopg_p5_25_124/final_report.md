# Audit Report

**Total findings:** 5

## Medium (4)

### F-001: Caller-controlled allowance targets can leave persistent approvals that later drain stranded tokens

**Confidence:** medium | **Locations:** `onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:138, onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:143`

`zap()` lets the caller choose both `allowanceTarget` and `swapTarget`, approves `inputToken` for the chosen spender, and then performs an arbitrary low-level call to a potentially different target. Because the approved spender does not need to be the contract that is actually called, a caller can intentionally leave a live allowance on the zapper without spending it.

**Impact:** Any same-token balance that later becomes stranded in the zapper can be stolen by the approved spender via `transferFrom` before governance sweeps it. Realistic sources of stranded balance include mistaken transfers, airdrops, overpaid native ETH handling, and other token-movement failures.

**Paths:**

- Attacker calls `zapOut` with `allowanceTarget` set to an attacker-controlled spender, `swapTarget` set to a no-op address/contract, and `minAmountOut = 0`

- `completeWithdrawalWithZap` credits want tokens to the zapper; `zap()` approves the attacker-controlled spender for `zapCall.amountIn`, but the low-level call does not consume the allowance

- The allowance persists after the transaction and the attacker later uses `transferFrom(zapper, attacker, amount)` to drain any future stranded balance of that token

*Round 1 | Agents: codex_1, merge_reviewer*

---

### F-002: Unchecked ERC20 return values allow silent transfer and approval failures

**Confidence:** high | **Locations:** `onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:53, onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:61, onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:76, onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:105, onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:108, onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:138`

Although `SafeERC20` is imported, the contract uses raw `transferFrom`, `transfer`, and `approve` calls and ignores their boolean return values. On false-returning or otherwise non-standard ERC20s, zap flows can continue after a failed transfer/approval instead of reverting.

**Impact:** Users can be left unpaid while `zapOut` still succeeds, governance `sweep` can silently fail to recover funds, and stale balances or stale allowances already held by the zapper can be consumed in later zaps when the expected token movement did not actually occur.

**Paths:**

- `zapOut` computes `amountOut` and then calls `IERC20(zapCall.requiredToken).transfer(msg.sender, amountOut)` without checking the return value, so a false-returning token can make the function emit success while transferring nothing

- `zapIn` uses unchecked `transferFrom`; if the token returns `false` and the zapper already holds enough of that token, the later balance check can still pass and the zap can consume residue that did not come from the caller

- Unchecked `approve` calls at lines 61 and 138 can silently fail, causing subsequent logic to rely on stale allowance state instead of a freshly set approval

*Round 1 | Agents: codex_1, opencode_1, merge_reviewer*

---

### F-003: Non-zero-to-non-zero approvals can permanently brick zero-first tokens on common routes

**Confidence:** medium | **Locations:** `onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:61, onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:138`

The contract overwrites allowances directly instead of zeroing them first or using safe allowance helpers. For tokens that require allowance to be reset to zero before setting a new non-zero value, any leftover allowance causes subsequent zaps on the same token/spender pair to revert.

**Impact:** An attacker can permissionlessly DoS future zap routes for zero-first tokens by intentionally planting residual allowance on a commonly used router/spender. If the frontend or integrators rely on that spender, zaps for that asset can remain bricked until the allowance is somehow consumed.

**Paths:**

- Attacker calls a zap using a zero-first token, sets `allowanceTarget` to a canonical router, sets `swapTarget` to a no-op target, and leaves a non-zero allowance behind

- A later user tries the same token/spender route; `approve(router, newAmount)` attempts a non-zero-to-non-zero update and reverts on USDT-style tokens

- Because the contract has no allowance-reset path, the affected route can remain unusable

*Round 1 | Agents: codex_1, opencode_1, merge_reviewer*

---

### F-005: zapOut uses the requested withdrawal amount instead of the amount actually delivered by the batcher

**Confidence:** low | **Locations:** `onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:74, onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:133, onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:138`

After `completeWithdrawalWithZap(zapCall.amountIn, msg.sender)`, the zapper never measures how many want tokens it actually received. It only checks whether its current want-token balance is at least the caller-supplied nominal `zapCall.amountIn`, then approves and swaps that full nominal amount.

**Impact:** If the batcher ever under-delivers, rounds down, or partially fulfills while the zapper already holds residual want tokens, the caller can consume that residue as if it were part of their own withdrawal. This can misattribute previously stranded funds to the next zap-out caller.

**Paths:**

- The zapper already holds some residual want tokens from earlier overpayments, accidental transfers, or failed token movements

- A caller invokes `zapOut` with `amountIn` greater than the batcher actually transfers in this transaction

- Because the contract checks only total current balance, `zap()` can approve and swap the residual balance together with the fresh withdrawal, effectively subsidizing the caller with pre-existing funds

*Round 1 | Agents: codex_1, opencode_1, merge_reviewer*

---

## Low (1)

### F-004: Native-ETH zaps accept overpayment and trap the surplus for governance

**Confidence:** high | **Locations:** `onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:98, onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:126, onchain_auto/0xd248b30a3207a766d318c7a87f5cf334a439446d/src/Zapper.sol:128`

For native-ETH zap-ins, the contract only checks `msg.value >= zapCall.amountIn` and forwards exactly `zapCall.amountIn` to the swap target. Any excess ETH sent by the user remains on the zapper with no refund path for the caller.

**Impact:** Users who overpay ETH lose the surplus immediately, and governance can later capture that stranded ETH through `sweep(nativeETH)`.

**Paths:**

- User calls `zapIn` with `requiredToken == nativeETH` and `msg.value > zapCall.amountIn`

- `zap()` forwards only `zapCall.amountIn` in the low-level call and leaves the extra ETH on the contract

- The surplus remains stranded until governance sweeps it

*Round 1 | Agents: codex_1, opencode_1, merge_reviewer*

---
