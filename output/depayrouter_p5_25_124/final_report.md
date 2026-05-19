# Audit Report

**Total findings:** 3

## High (2)

### F-001: Routes can return success without delivering any output, trapping user funds in the router

**Confidence:** high | **Locations:** `0xae60ac8e69414c2dc362d0e6a03af643d1d85b92/Contract.sol:743, 0xae60ac8e69414c2dc362d0e6a03af643d1d85b92/Contract.sol:761, 0xae60ac8e69414c2dc362d0e6a03af643d1d85b92/Contract.sol:784, 0xae60ac8e69414c2dc362d0e6a03af643d1d85b92/Contract.sol:812, 0xae60ac8e69414c2dc362d0e6a03af643d1d85b92/Contract.sol:840, 0xe04b08dfc6caa0f4ec523a3ae283ece7efe00019/Contract.sol:507, 0xe04b08dfc6caa0f4ec523a3ae283ece7efe00019/Contract.sol:522`

`route` only checks that the router's own balance of `path[path.length-1]` is not lower after execution; it never verifies that any recipient was paid or even that any plugin actually forwarded the output. The in-scope Uniswap plugin always sets the swap recipient to `address(this)`, and `route` also permits an empty `plugins` array, so calls can return `true` while all received or swapped assets remain stranded inside the router.

**Impact:** Users can lose the full value of their input while the transaction appears successful. The trapped assets remain under router custody and are recoverable only through the owner-only `withdraw`, creating direct fund-loss risk from malformed, buggy, or malicious integrations.

**Paths:**

- Call `route` with an empty `plugins` array. `_ensureTransferIn` pulls the user's asset, `_execute` does nothing, and `_ensureBalance` still passes because the router did not lose `tokenOut`.

- Call `route` with the Uniswap plugin as the only plugin. The swap sends output to `address(this)`, `_ensureBalance` passes because the router's own `tokenOut` balance increased, and no later step transfers the output to the intended recipient.

*Round 1 | Agents: codex_1*

---

### F-002: ERC20 input shortfalls are not measured, allowing routes to spend pre-existing router balances

**Confidence:** medium | **Locations:** `0xae60ac8e69414c2dc362d0e6a03af643d1d85b92/Contract.sol:775, 0xae60ac8e69414c2dc362d0e6a03af643d1d85b92/Contract.sol:779, 0xe04b08dfc6caa0f4ec523a3ae283ece7efe00019/Contract.sol:487, 0xe04b08dfc6caa0f4ec523a3ae283ece7efe00019/Contract.sol:515, 0xe04b08dfc6caa0f4ec523a3ae283ece7efe00019/Contract.sol:523`

For ERC20 input, `_ensureTransferIn` trusts `transferFrom` success and never checks how many tokens actually arrived. A fee-on-transfer, rebasing, or malicious token can deliver less than `amounts[0]`, while the Uniswap plugin still swaps exactly `amounts[0]` from the router context via `delegatecall`, consuming any pre-existing router balance of `path[0]` to cover the deficit.

**Impact:** Any stranded reserves, accidental deposits, or previously trapped user balances of the input token can be permissionlessly stolen to subsidize a later route. This breaks router solvency and can turn prior stuck funds into direct attacker profit once the router holds inventory.

**Paths:**

- The router already holds some balance of `path[0]` from prior trapped funds or accidental transfers.

- An attacker routes through a token whose `transferFrom` reports success but transfers less than `amounts[0]`.

- The Uniswap plugin executes `swapExactTokensForETH` or `swapExactTokensForTokens` for the full `amounts[0]`, causing the router's pre-existing `path[0]` balance to fund the shortfall.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-004: Excess ETH sent with a route is silently trapped and later owner-withdrawable

**Confidence:** high | **Locations:** `0xae60ac8e69414c2dc362d0e6a03af643d1d85b92/Contract.sol:759, 0xae60ac8e69414c2dc362d0e6a03af643d1d85b92/Contract.sol:768, 0xae60ac8e69414c2dc362d0e6a03af643d1d85b92/Contract.sol:776, 0xae60ac8e69414c2dc362d0e6a03af643d1d85b92/Contract.sol:840, 0xe04b08dfc6caa0f4ec523a3ae283ece7efe00019/Contract.sol:507`

For ETH input, the router only requires `msg.value >= amounts[0]`. `_balanceBefore` subtracts the full `msg.value` from the ETH pre-balance snapshot, while the Uniswap plugin spends only `amounts[0]` in `swapExactETHForTokens`. Any surplus ETH is neither refunded nor covered by the final balance check, so it remains trapped in the router.

**Impact:** Users or integrators that overpay ETH lose the entire surplus. The route still returns success, and the stuck ETH can later be extracted through the owner-only `withdraw` function.

**Paths:**

- Call `route` with `path[0] == ETH`, `msg.value > amounts[0]`, and a plugin path that only consumes `amounts[0]` ETH.

- The swap spends `amounts[0]`, the excess ETH remains in the router, and `_ensureBalance` does not enforce any refund.

- The owner later withdraws the trapped ETH through `withdraw`.

*Round 1 | Agents: codex_1*

---
