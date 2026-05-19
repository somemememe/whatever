# Audit Report

**Total findings:** 6

## High (3)

### C-001: Cross-chain handlers trust unbound token and swap metadata, enabling withdrawals of unrelated contract-held assets

**Confidence:** high | **Locations:** `GatewaySend.sol:248, GatewaySend.sol:297, GatewaySend.sol:341, GatewaySend.sol:358, GatewaySend.sol:363, GatewaySend.sol:366, GatewaySend.sol:369, GatewaySend.sol:372, GatewayCrossChain.sol:364, GatewayCrossChain.sol:469, GatewayCrossChain.sol:480, GatewayCrossChain.sol:492, GatewayCrossChain.sol:496, GatewayCrossChain.sol:517, GatewayTransferNative.sol:376, GatewayTransferNative.sol:386, GatewayTransferNative.sol:414, GatewayTransferNative.sol:422, GatewayTransferNative.sol:444, GatewayTransferNative.sol:449, GatewayTransferNative.sol:549, GatewayTransferNative.sol:554, GatewayTransferNative.sol:562, GatewayTransferNative.sol:574, libraries/SwapDataHelperLib.sol:56, libraries/SwapDataHelperLib.sol:97, libraries/SwapDataHelperLib.sol:108, libraries/SwapDataHelperLib.sol:112, libraries/SwapDataHelperLib.sol:133, libraries/SwapDataHelperLib.sol:140, libraries/SwapDataHelperLib.sol:144`

`GatewaySend`, `GatewayCrossChain`, and `GatewayTransferNative` all decode destination-side token metadata and DODO swap parameters directly from user-controlled messages without binding them to the asset and amount actually delivered for that call. `GatewaySend.onCall` trusts user-supplied `amount`, `fromToken`, `toToken`, and `swapData`; the Zeta-side contracts trust decoded `targetZRC20` and `MixSwapParams` without enforcing that `params.fromToken` equals the received `zrc20`, that `params.fromTokenAmount` matches the funded amount, or that the asset produced by `_doMixSwap` matches the later transferred/withdrawn token. Because the empty-swap path simply returns the caller-controlled `amount`, and because sentinel/forged metadata can skip the only input pull, an attacker can make the contracts transfer or withdraw unrelated balances they already hold.

**Impact:** Any ERC20, ZRC20, WZETA/native, or other residual inventory held by these gateway contracts can be exfiltrated. Attackers can bridge or message in one asset but receive a different contract-held asset, or even withdraw without funding the flow first, causing direct theft of stranded or pooled balances.

**Paths:**

- Call either `GatewaySend.depositAndCall(...)` entrypoint with a payload that encodes attacker-chosen `amount`, recipient, `fromToken = _ETH_ADDRESS_`, `toToken = victim asset`, and empty `swapData`; when `GatewaySend.onCall` executes, it skips the gateway pull, treats the forged `amount` as real output, and transfers the victim asset or ETH from its own balance.

- Trigger `GatewayCrossChain.onCall` with a message whose decoded `targetZRC20` points to a token already held by the contract and whose `swapDataZ` is empty or forged; `_doMixSwap` returns the nominal amount unchanged, after which `_handleBitcoinWithdraw` or `_handleEvmOrSolanaWithdraw` approves and withdraws/transfers `targetZRC20` from existing balances.

- Call `GatewayTransferNative.withdrawToNativeChain(_ETH_ADDRESS_, amount, message)` or reach `GatewayTransferNative.onCall` with forged `targetZRC20`/swap metadata; because the ETH-sentinel path skips `transferFrom` and empty swap data returns `amount`, the contract proceeds to transfer or withdraw attacker-selected assets from its own holdings.

*Round 2 | Agents: codex_1*

---

### F-002: Refund metadata truncates non-EVM recipients to 20 bytes and misdirects failed native withdrawals

**Confidence:** high | **Locations:** `GatewayCrossChain.sol:304, GatewayCrossChain.sol:318, GatewayCrossChain.sol:544, GatewayCrossChain.sol:550, GatewayTransferNative.sol:305, GatewayTransferNative.sol:319, GatewayTransferNative.sol:626, GatewayTransferNative.sol:631`

Both gateway contracts encode the revert recipient for `withdraw()` as `bytes.concat(externalId, bytes20(sender))`. If `sender` is a Bitcoin, Solana, or other non-20-byte address, it is silently truncated to 20 bytes. Later, `onRevert()` interprets every 52-byte revert payload as an EVM address and immediately transfers the refund to `address(uint160(bytes20(walletAddress)))` instead of preserving the original foreign-chain recipient bytes for later recovery.

**Impact:** When a native-chain withdrawal for a non-EVM recipient reverts, the refund can be sent to an unrelated EVM address derived from the first 20 bytes of that foreign address. Users can permanently lose funds through misdirected refunds.

**Paths:**

- Initiate a `withdraw()` flow whose `sender` or recipient bytes are longer than 20 bytes, such as a Bitcoin or Solana address.

- If the gateway reverts the withdrawal, the revert message is still only 52 bytes long because `bytes20(sender)` was stored.

- The contract treats that revert as an EVM refund and transfers the assets to the truncated 20-byte address instead of recording a claimable refund for the real non-EVM recipient.

*Round 1 | Agents: codex_1*

---

### F-001: GatewaySend cannot receive authenticated gateway calls because `onCall` returns the wrong ABI type

**Confidence:** high | **Locations:** `GatewaySend.sol:341`

`GatewaySend.onCall` is declared `returns (bytes4)`, but `GatewayEVM` performs authenticated deliveries through the `Callable` interface, which expects `onCall(MessageContext,bytes) returns (bytes memory)`. The function selector is the same, so the call reaches `GatewaySend`, but the gateway-side Solidity call then ABI-decodes the returndata as dynamic bytes. `GatewaySend` instead ABI-encodes a fixed-size `bytes4` return value, so authenticated deliveries revert during return-data decoding even when the body of `onCall` succeeds.

**Impact:** Authenticated cross-chain deliveries into `GatewaySend` are bricked. Transfers routed through `GatewayEVM.execute(...)/_executeAuthenticatedCall(...)` cannot settle normally and instead fail into revert handling.

**Paths:**

- A cross-chain flow reaches `GatewayEVM.execute(...)` with a nonzero `messageContext.sender` for authenticated delivery.

- `GatewayEVM._executeAuthenticatedCall(...)` invokes `Callable(destination).onCall(messageContext, data)` and expects ABI-encoded `bytes` returndata.

- `GatewaySend.onCall(...)` returns a fixed `bytes4` value instead, causing the caller-side decode to revert and the authenticated delivery to fail.

*Round 3 | Agents: codex_1*

---

## Medium (3)

### F-005: GatewayTransferNative refund claims are reentrant and can be claimed multiple times before state deletion

**Confidence:** high | **Locations:** `GatewayTransferNative.sol:680, GatewayTransferNative.sol:691, GatewayTransferNative.sol:692`

`GatewayTransferNative.claimRefund` performs the external token transfer before deleting `refundInfos[externalId]`. If the refund token is a malicious ERC20/ZRC20, its `transfer` logic can reenter `claimRefund` while the refund entry still exists and pull the same refund repeatedly.

**Impact:** A claimant controlling the refund receiver and token contract can drain the contract's balance of the refunded asset far beyond the intended single refund amount.

**Paths:**

- A revert or abort stores a refund entry in `refundInfos`.

- The attacker calls `claimRefund` for a refund whose token executes arbitrary code during `transfer`.

- The token reenters `claimRefund` before `delete refundInfos[externalId]` runs, allowing repeated transfers against the same refund record.

*Round 2 | Agents: codex_1*

---

### F-006: Fee-on-transfer tokens are over-credited, letting callers spend prior balances held by the contracts

**Confidence:** high | **Locations:** `GatewaySend.sol:239, GatewaySend.sol:245, GatewaySend.sol:317, GatewaySend.sol:320, GatewayTransferNative.sol:555, GatewayTransferNative.sol:570, GatewayTransferNative.sol:574`

The direct deposit entrypoints assume `transferFrom(..., amount)` delivers exactly `amount`, then immediately swap, fee, or bridge using the nominal input instead of the actual balance delta. With fee-on-transfer or deflationary tokens, the shortfall is silently sourced from whatever balance of that token the contract already holds.

**Impact:** A user can underpay while consuming prior users' or protocol-owned token balances. Depending on the token inventory already present, this can produce value extraction, inconsistent accounting, or denial of service when the contract later runs short.

**Paths:**

- Call `GatewaySend.depositAndCall(fromToken, amount, ...)` with a fee-on-transfer ERC20 so the contract receives less than `amount` but still swaps or deposits using the full nominal value.

- Call `GatewaySend.depositAndCall(targetContract, amount, asset, ...)` with a fee-on-transfer ERC20 so the gateway deposit is funded partly from pre-existing contract balance.

- Call `GatewayTransferNative.withdrawToNativeChain(zrc20, amount, ...)` with a fee-on-transfer ZRC20 so platform fee handling and downstream withdrawal logic spend more than was actually received.

*Round 2 | Agents: codex_1*

---

### F-007: ETH revert refunds on GatewaySend are recorded as ERC20 transfers and remain stuck in the contract

**Confidence:** high | **Locations:** `GatewaySend.sol:249, GatewaySend.sol:304, GatewaySend.sol:393, GatewaySend.sol:396`

The ETH-based `depositAndCall` flows set `callOnRevert = true`, and `GatewayEVM.executeRevert` forwards the refunded ETH as `msg.value` while setting `context.asset` to `address(0)`. `GatewaySend.onRevert` does not special-case native ETH and always calls `TransferHelper.safeTransfer(context.asset, sender, context.amount)`. A low-level call to `address(0)` with ERC20 transfer calldata succeeds without moving ETH, so the refund handler completes while the ETH remains stranded on `GatewaySend`.

**Impact:** When an ETH bridge operation reverts, the user is not repaid through the normal revert path and the refunded ETH accumulates on `GatewaySend` until recovered by a code change or privileged/manual intervention.

**Paths:**

- Call `GatewaySend.depositAndCall(...ETH...)` so the source-side gateway emits a revertable ETH transfer.

- Cause the destination-side operation to fail, leading `GatewayEVM.executeRevert(...)` to invoke `GatewaySend.onRevert(...)` with native ETH and `context.asset == address(0)`.

- `GatewaySend.onRevert(...)` performs an ERC20-style transfer against the zero address instead of forwarding ETH, leaving the refunded ETH stuck in the contract.

*Round 3 | Agents: codex_1*

---
