# Audit Report

**Total findings:** 6

## Critical (2)

### F-001: Missing initializer leaves ownership and core token state unset, permanently bricking the token

**Confidence:** high | **Locations:** `0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:18, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:38, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:127, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/State.sol:39, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/State.sol:42, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/State.sol:45, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/State.sol:46, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/Getters2.sol:86`

`XStable2` inherits `Initializable` and `OwnableUpgradeable` but exposes no constructor or initializer that seeds `_owner`, `_largeTotal`, `_presaleCon`, `_presaleDone`, or the other required boot-time state. In the reviewed source there is no reachable code path that calls `__Ownable_init()` or assigns those storage variables. As deployed from this source, `owner()` remains the zero address, presale minting is unreachable because `_presaleCon` stays zero, transfers are blocked forever by `require(isPresaleDone())`, and `getFactor()` returns `_largeTotal / launchSupply = 0`, causing `balanceOf`/`unlockedBalanceOf`/`circulatingSupply` to divide by zero.

**Impact:** The token is unrecoverably unusable from its own code path: admin-only functions can never be called, presale minting can never start, transfers can never start, and even basic balance queries revert once they hit `getFactor()`. This is a full protocol brick.

**Paths:**

- Deploy `XStable2` from the reviewed source

- Call `balanceOf(any)` or `unlockedBalanceOf(any)`; `getFactor()` returns `0` and the division reverts

- Call any `onlyOwner` function such as `createTokenPool()` or `pauseContract()`; `owner()` is never initialized so access is permanently impossible

- Call `mint(to, amount)`; `onlyPresale` can never pass because `_presaleCon` remains `address(0)`

*Round 1 | Agents: codex_1, opencode_1*

---

### F-003: Mint and burn logic is manipulable because it trusts raw instantaneous pair balances and public counter sync

**Confidence:** medium | **Locations:** `0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/Getters2.sol:93, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/Getters2.sol:99, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/Setters2.sol:33, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/Setters2.sol:41, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:142, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:145, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:331, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:358`

Pool state is derived from raw `IERC20.balanceOf(pool)` and `IERC20(pairToken).balanceOf(pool)` snapshots, not from AMM reserves or a TWAP, and anyone can refresh those counters through `silentSyncPair()`. The resulting balances directly drive the quadratic `expansionR` mint formula on buys and the contraction formula on sells. Because these are instantaneous balances with no slippage bound, cap, or time averaging, an attacker can temporarily skew them with a flash loan or transient pool-balance manipulation and force an outsized mint or burn regime.

**Impact:** An attacker can create artificially favorable mint conditions, trigger a huge positive rebase on a supported-pool buy, and then dump the inflated position into pool liquidity. The same oracle weakness can also force excessive burns or transaction failures on sell paths. This enables realistic liquidity extraction and severe economic manipulation.

**Paths:**

- Temporarily skew a supported pool's token or pair-token balances with a flash loan or other transient balance manipulation

- Call or wait for `syncPair()`/`silentSyncPair()` so `_poolCounters` capture the manipulated balances

- Trigger a supported-pool buy; `_implementBuy()` calls `getMintValue()` and mints based on the manipulated `expansionR`

- Exit via sell/arbitrage before balances normalize, externalizing the loss to holders and pool liquidity

*Round 1 | Agents: codex_1, merge_review*

---

## High (3)

### F-002: `_mainPool` is never assigned, so ordinary transfers and unsupported-recipient sells revert

**Confidence:** high | **Locations:** `0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/State.sol:23, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:144, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:147, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:156, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:361, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/Setters2.sol:41`

The token relies on `_mainPool` as the fallback pricing source whenever a transfer is neither a supported-pool buy nor a supported-pool sell, but `_mainPool` is only declared and read. The reviewed source contains no assignment, setter, or initializer for `_mainPool`. As a result, wallet-to-wallet transfers call `silentSyncPair(_mainPool)` on `address(0)`, and unsupported-recipient sell logic reads zeroed `_poolCounters[address(0)]` values and divides by zero in `getBurnValues()`.

**Impact:** Even if the rest of the deployment state were repaired externally, normal ERC20 transfers remain permissionlessly DoSed and many sell paths remain broken. Users are forced into a narrow subset of supported-pool interactions instead of a functioning token.

**Paths:**

- Assume transfers are enabled

- User calls `transfer()` between two non-pool addresses

- `_transfer()` falls into the fallback branch and executes `silentSyncPair(_mainPool)` with `_mainPool == address(0)`, reverting on external calls to `address(0)`

- If a transfer reaches `getBurnValues()` for an unsupported recipient, the fallback path uses `_poolCounters[_mainPool]` and hits zero-denominator math

*Round 1 | Agents: codex_1, opencode_1*

---

### F-004: Epoch rollover snapshots stale counters before refreshing pool state, allowing poisoned baselines for an entire epoch

**Confidence:** medium | **Locations:** `0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:134, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:143, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:145, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/Setters2.sol:26, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/Setters2.sol:29, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/Setters2.sol:41, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/Getters2.sol:93`

When an epoch expires, `_transfer()` executes `updateEpoch()` before it refreshes any pool via `syncPair()` or `silentSyncPair()`. `updateEpoch()` therefore copies whatever stale cached balances are currently stored in `_poolCounters` into `startTokenBalance` and `startPairTokenBalance`. An attacker who lets cached counters drift, or who manipulates balances around the boundary, can cause the first post-expiry transfer to lock in a distorted baseline for the full next epoch.

**Impact:** Buy-mint and sell-burn calculations for the next four hours can be biased upward or downward for the attacker, causing repeated over-minting, over-burning, or broken trading conditions across the entire epoch.

**Paths:**

- Allow a supported pool's cached counters to become stale or manipulate balances near an epoch boundary

- Trigger the first transfer after `currentEpoch + epochLength`

- `updateEpoch()` stores the stale counters as the new `start*` baseline before any fresh sync occurs

- The later sync in the same transfer updates only the current balances, so subsequent mint/burn math uses a poisoned baseline for the rest of the epoch

*Round 1 | Agents: codex_1*

---

### F-005: Pool creation is fully sandwichable because swap and liquidity add both use zero slippage protection

**Confidence:** high | **Locations:** `0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:249, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:269, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:274`

`createTokenPool()` swaps half of the contract's XST with `amountOutMin = 0` and then adds liquidity with `amountAMin = 0` and `amountBMin = 0`. Those zero bounds let MEV searchers move the route price immediately before execution and force the contract to accept arbitrarily bad execution on both the swap and the liquidity add.

**Impact:** A sandwich attacker can siphon a meaningful portion of the protocol's pool-seeding inventory and can launch the new pool at a manipulated price, harming the treasury and all later traders.

**Paths:**

- Watch for an owner call to `createTokenPool()`

- Front-run by moving the XST/WETH or WETH/pairToken route against the contract

- The contract executes `swapExactTokensForTokensSupportingFeeOnTransferTokens(..., 0, ...)` and `addLiquidity(..., 0, 0, ...)` at the manipulated price

- Back-run to restore the market and keep the extracted value

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-006: Updating the liquidity reserve burns and strands protocol funds because the migration transfer is taxed

**Confidence:** high | **Locations:** `0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:156, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:186, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:195, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:300, 0xb276647e70cb3b81a1ca302cf8de280ff0ce5799/C/Crypto/Projects/xstable/contracts/XST2.sol:308`

`setLiquidityReserve()` removes the old reserve's taxless status and then migrates its balance with a normal `_transfer()`, unlike `setStabilizer()` which wraps the move in `taxlessTx`. Because the `_liquidityReserve` pointer is only updated after the transfer, the migration is treated as a taxed txType-2 transfer: part of the balance is burned, part goes into the incentive pot, and the utility fee is credited back to the old reserve rather than the new one.

**Impact:** A routine admin reserve migration permanently destroys part of the protocol's reserve inventory and can leave a residue stranded at the old reserve address. If that old reserve is not directly recoverable, those tokens are lost.

**Paths:**

- Old liquidity reserve holds XST and owner calls `setLiquidityReserve(newReserve)`

- Function clears `_isTaxlessSetter[_liquidityReserve]` before moving the balance

- `_transfer(oldReserve, newReserve, oldBalance)` executes through the taxed sell/unsupported-transfer path, applying burn and pot logic

- Only after the taxed transfer does `_liquidityReserve = newReserve`, so the fee credit went to the old reserve and the burned/pot portions are unrecoverable

*Round 1 | Agents: merge_review*

---
