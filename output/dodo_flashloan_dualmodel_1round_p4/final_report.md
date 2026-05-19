# Audit Report

**Total findings:** 5

## Critical (2)

### F-001: Pool initialization is permissionless and can be replayed at any time

**Confidence:** high | **Locations:** `onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:1415, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:1424, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:1454`

`DVM.init()` is externally callable with no access control and no one-time initialization guard. Any address can initialize an uninitialized pool or re-call `init()` on a live pool to overwrite the maintainer, token addresses, fee model, PMM parameters, TWAP mode, and permit domain separator.

**Impact:** An attacker can seize a fresh deployment before the intended operator or reconfigure a funded pool into attacker-controlled parameters. That can redirect maintainer fees, manipulate pricing/fee settings to extract reserves, or repoint the pool to different token addresses and strand the real assets already held by the contract.

**Paths:**

- Front-run the intended initializer and call `init()` first with attacker-chosen tokens, fee model, maintainer, `i`, `k`, and TWAP settings.

- Re-call `init()` on a live pool using attacker-favorable parameters, then trade or flash-loan against the misconfigured pool to extract value.

- Re-call `init()` with different token addresses so accounting no longer tracks the real tokens already held by the contract, permanently trapping existing funds.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-002: Ambient balance-delta accounting lets anyone steal pending swap or liquidity deposits

**Confidence:** high | **Locations:** `onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:910, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:922, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:926, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:1169, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:1193, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:1323, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:1363`

The pool never pulls assets from `msg.sender`. `sellBase()`, `sellQuote()`, and `buyShares()` treat any token balance above stored reserves as the current caller's input, while `sellShares()` redeems against total live balances rather than protected reserves. This makes pre-transferred or accidentally transferred tokens claimable by whoever calls the state-changing entrypoint next.

**Impact:** A third party can front-run or back-run users who seed the pool in two steps and steal the victim's deposited assets or the outputs generated from them. Initial liquidity, ordinary swaps, and pending liquidity additions can all be fully hijacked, and exiting LPs can also siphon a pro-rata share of someone else's pending deposit.

**Paths:**

- A victim transfers base tokens to the pool, intending to call `sellBase()` next; an attacker calls `sellBase(attacker)` first and receives the quote output for the victim's base deposit.

- A victim transfers base and quote tokens before calling `buyShares()`; an attacker front-runs with `buyShares(attacker)` and mints LP shares backed by the victim's tokens.

- While user deposits are sitting in the contract but reserves are not yet updated, an LP calls `sellShares()` and withdraws a pro-rata slice of those pending deposits.

*Round 1 | Agents: codex_1*

---

## High (1)

### F-003: TWAP oracle is poisonable because cumulative price uses post-update reserves

**Confidence:** high | **Locations:** `onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:932, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:943, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:951`

Both `_setReserve()` and `_sync()` write the new reserves before calling `_twapUpdate()`. `_twapUpdate()` then accrues the entire elapsed time since the last update using the latest reserves instead of the old reserves that actually prevailed during that interval.

**Impact:** After a long quiet period, an attacker can manipulate the pool price shortly before triggering `_setReserve()` or `_sync()` and backfill that manipulated price across the whole stale window. Any downstream consumer relying on `_BASE_PRICE_CUMULATIVE_LAST_` can then read a severely distorted TWAP, leading to bad pricing, liquidations, or other oracle-driven losses.

**Paths:**

- Wait until TWAP has not been updated for a meaningful period.

- Manipulate pool balances or spot price with a swap, flash-loan repayment pattern, or direct token transfer.

- Call `sync()` or any path that reaches `_setReserve()` so the manipulated reserves are used for the full elapsed interval.

- Restore the spot price afterward while leaving the cumulative oracle poisoned.

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-004: Fee-tier checks use `tx.origin`, making privileged fee rates transferable and phishable

**Confidence:** medium | **Locations:** `onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:1177, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:1201, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:1241, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:1258`

Trading and flash-loan repayment paths compute fees using `tx.origin` instead of the actual caller or economic beneficiary. Any contract that can induce a privileged EOA to originate a transaction inherits that EOA's fee tier when interacting with the pool.

**Impact:** Whitelisted or discounted fee treatment becomes transferable to arbitrary contracts and can be phished from privileged EOAs. This weakens fee enforcement, reduces maintainer revenue, and can change flash-loan repayment thresholds or other fee-sensitive behavior for transactions that the privileged user did not intend to subsidize.

**Paths:**

- A VIP or fee-whitelisted EOA calls an attacker-controlled contract.

- The attacker-controlled contract forwards a trade or flash-loan interaction into the pool.

- The pool prices the action using the victim EOA's fee tier because it keys off `tx.origin` rather than the real caller.

*Round 1 | Agents: codex_1*

---

### F-006: Initial share minting ignores quote-side value, allowing theft of trapped quote balances

**Confidence:** high | **Locations:** `onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:1339, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:1343, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:1347, onchain_auto/0x051ebd717311350f1684f89335bed4abd083a2b6/Contract.sol:1350`

When `totalSupply == 0`, `buyShares()` mints shares solely from `baseBalance` and does not require matching quote input. As a result, any quote tokens already held by the contract are not valued during bootstrap and are captured by whoever performs the next initial mint.

**Impact:** Residual quote dust after all LP shares are burned, accidental quote transfers into an empty pool, or quote balances stranded by other edge cases can be stolen by the next minter for only the minimum base deposit. The attacker receives 100% of LP shares and can immediately redeem the trapped quote tokens.

**Paths:**

- The pool reaches `totalSupply == 0` while still holding nonzero quote tokens, or someone accidentally transfers quote tokens to an empty pool.

- An attacker deposits the minimum required base amount and calls `buyShares(attacker)`.

- Because initial minting only prices the base side, the attacker receives the entire LP supply and then redeems the trapped quote balance via `sellShares()`.

*Round 1 | Agents: codex_1*

---
