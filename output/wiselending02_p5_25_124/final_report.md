# Audit Report

**Total findings:** 6

## High (3)

### F-001: depositExactAmountETHMint skips pool synchronization and mints WETH shares at stale prices

**Confidence:** high | **Locations:** `0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:364, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:383`

`depositExactAmountETHMint()` calls `_depositExactAmountETH()` directly, unlike `depositExactAmountETH()` which is wrapped in `syncPool(WETH_ADDRESS)`. As a result, WETH deposits through the minting path skip `_preparePool`, interest accrual, cleanup of excess balance, share-price snapshotting, and the post-action share-price invariant. If the WETH pool has accrued yield or interest since the last sync, the function mints shares against stale `pseudoTotalPool` state.

**Impact:** An attacker can mint underpriced WETH lending shares, then redeem them after a later sync for more WETH than they should receive. This steals accrued yield from existing WETH lenders and can also bypass deposit-cap enforcement that depends on current pool totals.

**Paths:**

- Wait until the WETH pool has accrued interest/yield without being synced.

- Call `depositExactAmountETHMint()` instead of the synchronized `depositExactAmountETH()` path.

- Receive shares calculated from stale WETH pool totals.

- Redeem those shares after any later sync to extract excess WETH from the pool.

*Round 1 | Agents: codex_1*

---

### F-002: Inbound ERC20 accounting uses the requested amount instead of the actual tokens received

**Confidence:** high | **Locations:** `0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:142, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:566, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:589, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:432, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:510, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:578, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1277, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1318`

Deposits, solely deposits, repayments, and liquidation paybacks update pool and position accounting from the user-supplied `_amount`/`_paybackAmount` without reconciling against the contract's actual balance increase. For fee-on-transfer, deflationary, or otherwise non-plain ERC20s, the protocol credits more collateral or more debt repayment than it actually receives.

**Impact:** If such a token is ever listed, users can over-credit collateral and borrow against it, repay debt with fewer tokens than required, or liquidate positions while underpaying the protocol. The affected pools can become undercollateralized or insolvent, creating direct lender losses.

**Paths:**

- Use a transfer-tax or deflationary token as a listed collateral asset and call `depositExactAmount()` or `solelyDeposit()`.

- The protocol credits the full nominal `_amount` even though fewer tokens arrive.

- Borrow other assets against the inflated collateral balance.

- Or use a transfer-tax debt token in `paybackExactAmount()`, `paybackExactShares()`, or liquidation so debt is reduced by more than the protocol actually receives.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-003: ERC20 transfer helpers treat `false` return values as success

**Confidence:** high | **Locations:** `0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/TransferHub/CallOptionalReturn.sol:12, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/TransferHub/TransferHelper.sol:13, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/TransferHub/TransferHelper.sol:34, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:432, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:578, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:706, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:786, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1121, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1285, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:589, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:596`

`_callOptionalReturn()` only reverts when the low-level call itself fails. If a token call succeeds but returns `false`, the helper simply returns `false`; `_safeTransfer()` and `_safeTransferFrom()` ignore that return value, so execution continues as if the transfer succeeded.

**Impact:** For any listed token that signals failure by returning `false`, deposits and repayments can mint collateral credit or erase debt without moving funds. Outbound transfers can also burn shares or increase debt bookkeeping without actually paying the user or liquidator. This can create unbacked positions, lender losses, and stuck user funds.

**Paths:**

- Use a listed token whose `transferFrom` returns `false` on failure rather than reverting.

- Call deposit or payback functions that update internal accounting before the ignored return value is observed.

- Receive collateral credit or debt reduction even though no tokens were transferred.

- Use the unbacked position to borrow other pool assets, or trigger outbound paths where the protocol debits user state without a real token payout.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-004: Low-liquidity liquidation records seized lending shares under the victim NFT instead of the liquidator NFT

**Confidence:** high | **Locations:** `0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:437, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:499, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:585, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:634`

When a liquidation wants more collateral than the pool can immediately pay out, `_withdrawOrAllocateSharesLiquidation()` moves the residual lending shares to `_nftIdLiquidator`, but then calls `_addPositionTokenData()` with `_nftId` instead of `_nftIdLiquidator`. The liquidator receives the shares in `userLendingData`, yet the token-list bookkeeping is written against the victim position.

**Impact:** The liquidator's seized lending position can become invisible to later bookkeeping and cleanup logic. Subsequent withdrawals or other actions that rely on `positionLendTokenData` can corrupt array state or strand seized collateral, breaking post-liquidation fund recovery.

**Paths:**

- Liquidate a position where the desired receive token has insufficient liquid pool balance.

- The contract pays out the available pool tokens and transfers the residual claim as lending shares to the liquidator NFT.

- The token-list entry is added to the victim NFT instead of the liquidator NFT.

- Later liquidator actions on that asset encounter inconsistent bookkeeping and can fail or corrupt token-list cleanup.

*Round 1 | Agents: codex_1*

---

## Low (2)

### F-005: Position-token cleanup can break once a position tracks more than 256 assets

**Confidence:** medium | **Locations:** `0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:634, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:657`

`_removePositionData()` iterates over a dynamic token array with `uint8 i` and `unchecked` increments. If a position's lending or borrow token list grows beyond 256 entries, the counter wraps from 255 back to 0 and can no longer reach indices above 255 or an `endPosition` above 255.

**Impact:** Affected positions can become unable to clean up certain token entries, causing withdrawals, repayments, or liquidations that rely on token-list removal to revert or run out of gas. This is a position-level denial of service for large, long-lived portfolios.

**Paths:**

- Accumulate more than 256 tracked lending or borrow assets in a single NFT position.

- Trigger a flow that needs `_removePositionData()` for an entry beyond index 255.

- The `uint8` loop counter wraps before reaching the target or final index.

- Cleanup cannot complete, bricking the affected action path for that position.

*Round 1 | Agents: codex_1*

---

### F-006: Any verified isolation pool can arbitrarily lock or unlock unrelated positions

**Confidence:** medium | **Locations:** `0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1479, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/InterfaceHub/IWiseSecurity.sol:187`

`setRegistrationIsolationPool()` only checks that `msg.sender` is a verified isolation-pool contract, then writes `positionLocked[_nftId]` directly. It performs no local ownership or registration validation, and the `IWiseSecurity` interface exposes a `checksRegister()` hook that is not called here.

**Impact:** A buggy or compromised verified isolation-pool contract can lock or unlock arbitrary user NFTs outside its intended scope. That can freeze deposits, withdrawals, and paybacks for unrelated users, or clear locks unexpectedly and break isolation assumptions.

**Paths:**

- A verified isolation-pool contract calls `setRegistrationIsolationPool()` for an NFT it should not control.

- The call succeeds because the lending contract only verifies the caller's pool status, not the NFT relationship.

- The victim position is forcibly locked or unlocked.

- User actions that depend on `positionLocked` start reverting or isolation guarantees are weakened.

*Round 1 | Agents: codex_1*

---
