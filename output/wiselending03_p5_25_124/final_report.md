# Audit Report

**Total findings:** 5

## High (3)

### F-001: Transfer-in accounting trusts nominal amounts and ignores unsuccessful ERC20 return values

**Confidence:** high | **Locations:** `0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:114, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:416, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:495, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:556, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:720, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1255, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1299, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:545, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/TransferHub/CallOptionalReturn.sol:12`

Deposits, solely-deposits, paybacks, and liquidation payback legs update pool and position accounting from the caller-supplied `_amount` before the token transfer settles, while `_callOptionalReturn()` only reverts on low-level call failure and silently accepts ERC20s that return `false`. Fee-on-transfer, deflationary, false-return, or otherwise non-standard listed tokens can therefore mint too many lending shares or cancel too many borrow shares relative to the tokens the protocol actually receives.

**Impact:** If such a token is listed, an attacker can overmint claims on a pool, repay debt at a discount, or execute underfunded liquidations, pushing the shortfall onto lenders and other borrowers and potentially stealing pool value or causing insolvency.

**Paths:**

- depositExactAmount -> _handleDeposit -> _safeTransferFrom

- solelyDeposit -> _handleSolelyDeposit -> _safeTransferFrom

- paybackExactAmount/paybackExactShares -> _handlePayback -> _safeTransferFrom

- liquidatePartiallyFromTokens/coreLiquidationIsolationPools -> _coreLiquidation -> _corePayback -> _safeTransferFrom

*Round 1 | Agents: codex_1*

---

### F-002: depositExactAmountETHMint skips WETH pool synchronization and can mint shares at a stale price

**Confidence:** high | **Locations:** `0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:345, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:358, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:383, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:114`

`depositExactAmountETHMint()` calls `_depositExactAmountETH()` directly instead of going through the `syncPool(WETH_ADDRESS)` modifier used by `depositExactAmountETH()`. After interest accrues but before anyone syncs the WETH pool, this path still computes lending shares from stale `pseudoTotalPool` and borrow accrual state.

**Impact:** A user can mint excess WETH lending shares against an out-of-date pool state and later redeem them after synchronization, siphoning accrued interest from existing lenders.

**Paths:**

- depositExactAmountETHMint -> _depositExactAmountETH -> _handleDeposit

*Round 1 | Agents: codex_1*

---

### F-004: Verified isolation pools can bypass liquidation repayment invariants

**Confidence:** low | **Locations:** `0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1406, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1433, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:545, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:720`

`coreLiquidationIsolationPools()` accepts both `_paybackAmount` and `_shareAmountToPay` from a verified isolation-pool caller and forwards them straight into `_coreLiquidation()` / `_corePayback()` without recomputing `paybackAmount` from shares or running the normal `checksLiquidation()` path. A verified isolation pool can therefore burn arbitrary borrow shares for too little payment or otherwise execute liquidations on terms the public path would reject.

**Impact:** A buggy or compromised verified isolation pool can socialize losses onto the main lending markets by forgiving debt too cheaply or extracting collateral under invalid liquidation terms.

**Paths:**

- coreLiquidationIsolationPools -> _coreLiquidation -> _corePayback

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-003: Illiquid liquidation credits residual shares to the liquidator but records the token under the victim NFT

**Confidence:** high | **Locations:** `0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:437, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:493, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:499, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:634, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:1131`

When a liquidation cannot fully pay out in tokens, `_withdrawOrAllocateSharesLiquidation()` moves `shareDifference` to `_nftIdLiquidator` but calls `_addPositionTokenData()` with `_nftId` instead of `_nftIdLiquidator`. If the liquidator did not already track that token, later cleanup sees inconsistent token metadata, which can underflow on zero-length removal or delete the wrong token-list entry.

**Impact:** Seized shares can become untracked and hard to withdraw, or later withdrawals can corrupt the liquidator's position bookkeeping and strand funds.

**Paths:**

- liquidatePartiallyFromTokens/coreLiquidationIsolationPools -> _coreLiquidation -> _withdrawOrAllocateSharesLiquidation

- later withdrawExactAmount/withdrawExactShares -> _removeEmptyLendingData -> _removePositionData

*Round 1 | Agents: codex_1*

---

### F-005: Arbitrary NFT dusting combines with a uint8 loop to freeze position cleanup once enough markets are listed

**Confidence:** medium | **Locations:** `0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:416, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:495, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:556, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:634, 0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:657`

Deposit paths accept an arbitrary `_nftId` without ownership or approval checks, so anyone can append supported pool tokens to another user's position by dusting it. Once a position's tracked lending-token count exceeds 255, `_removePositionData()` iterates with a `uint8` counter inside an unchecked loop, causing the index to wrap to 0 and making removal/cleanup paths non-terminating.

**Impact:** If the protocol ever lists enough markets, an attacker can grief a victim position into a state where full withdrawals or other cleanup operations run out of gas, effectively freezing exits for that NFT.

**Paths:**

- attacker calls depositExactAmount/solelyDeposit into a victim NFT across many supported pools

- victim later fully exits a token position -> _removeEmptyLendingData -> _removePositionData

*Round 1 | Agents: codex_1*

---
