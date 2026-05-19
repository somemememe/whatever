# Audit Report

**Total findings:** 6

## High (3)

### F-001: Fungible oTokens can be exercised against attacker-chosen healthy vaults first

**Confidence:** high | **Locations:** `onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1491, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1505, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1508, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1816, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1869, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1890`

The oToken supply is fungible, but `exercise()` lets the caller choose the exact vault list and `_exercise()` debits only the selected vault's collateral and debt. Holders can therefore route identical oTokens to the healthiest vaults first instead of taking a pro-rata share of aggregate system collateral.

**Impact:** When vault quality diverges, sophisticated exercisers can drain the best-collateralized vaults and leave later exercisers backed only by weak or underwater vaults. This creates a bank-run dynamic and can materially worsen losses for later holders of the same fungible oToken.

**Paths:**

- Some vaults remain well collateralized while others are weak or underwater

- An attacker acquires oTokens and calls `exercise()` with only the healthiest vaults in `vaultsToExerciseFrom`

- `_exercise()` removes collateral and debt only from those selected vaults

- Later holders can only exercise against the remaining weak vaults, or fail once those vaults cannot cover payout plus fee

*Round 1 | Agents: codex_1*

---

### F-002: Uniswap trading helpers have effectively no slippage protection

**Confidence:** high | **Locations:** `onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:698, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:801, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:814, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:824, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:835, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:872, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:898`

The sell path hardcodes `min_eth` / `min_tokens_bought` to `1`, and the buy path computes the quoted input for a desired output but then executes Uniswap swaps with minimum outputs of `1`. Users get no meaningful execution bound on either side.

**Impact:** Buyers and sellers are fully exposed to sandwiching and reserve manipulation. A searcher can move the pool just before execution so sellers receive near-zero premium or buyers receive far fewer oTokens than expected while still spending the full quoted input.

**Paths:**

- A victim submits `sellOTokens()` or `buyOTokens()`

- An MEV actor front-runs to worsen the Uniswap price

- The helper still executes because all minimum outputs are effectively `1`

- The MEV actor back-runs to restore price and captures the victim's lost value

*Round 1 | Agents: codex_1, opencode_1*

---

### F-004: Zero oracle prices can freeze exercise and liquidation until writers reclaim collateral

**Confidence:** high | **Locations:** `onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:519, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1644, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1816, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1929, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1985, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:2025, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:2089`

The oracle interface explicitly permits `getPrice()` to return zero when an asset is unset or the oracle is paused, but the option logic never validates returned prices before dividing by them in safety, issuance, liquidation, and payout calculations.

**Impact:** If collateral or strike price becomes zero during the exercise window, critical flows such as exercise and liquidation can revert due to division by zero. If the outage persists until expiry, holders can be unable to claim while writers still recover remaining collateral and accumulated underlying through `redeemVaultBalance()`, causing realistic loss to option holders.

**Paths:**

- The oracle returns `0` for the collateral or strike asset during the live or exercise period

- `isSafe()`, `calculateOTokens()`, or `calculateCollateralToPay()` divides by the zero price and reverts

- Exercise and/or liquidation attempts fail for the duration of the outage

- After expiry, vault owners call `redeemVaultBalance()` and recover the vault balances while holders missed their exercise window

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (2)

### F-003: ETH oToken purchases spend contract balance instead of enforcing caller payment

**Confidence:** high | **Locations:** `onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:732, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:835, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:886, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:898, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:926`

In the ETH payment branch, neither `buyOTokens()` nor `uniswapBuyOToken()` validates `msg.value`. The contract instead forwards `ethToTransfer` from its own balance, and its payable fallback can accumulate ETH from overpayments, Uniswap refunds, or forced transfers.

**Impact:** Any ETH stranded in `OptionsExchange` can subsidize later callers. An attacker can buy oTokens with zero or insufficient ETH as long as the contract already holds enough ETH, effectively stealing trapped funds from prior users or accidental senders.

**Paths:**

- ETH becomes trapped in `OptionsExchange` via overpayment, Uniswap behavior, direct transfer, or forced send

- An attacker calls `buyOTokens(..., address(0), ...)` or directly calls `uniswapBuyOToken()` with ETH as the payment asset

- The helper spends the contract's existing ETH balance rather than enforcing fresh payment from the caller

- The attacker receives oTokens funded by someone else's stranded ETH

*Round 1 | Agents: codex_1, opencode_1*

---

### F-005: Payout helpers ignore ERC20 transfer return values and can silently erase claims

**Confidence:** high | **Locations:** `onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1530, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1659, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1660, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1755, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1890, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:2058, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:2071`

`transferCollateral()` and `transferUnderlying()` call ERC20 `transfer()` without checking the returned boolean. Several flows zero or decrement user balances before invoking these helpers.

**Impact:** For tokens that return `false` instead of reverting, the contract can clear a user's recorded collateral or underlying claim while sending nothing on-chain. Funds remain trapped in the contract and accounting becomes inconsistent across redeem, liquidation, exercise, and underlying-withdraw flows.

**Paths:**

- The collateral or underlying token returns `false` on `transfer()` rather than reverting

- The contract first zeroes or decreases the user's internal vault balance

- The unchecked transfer silently fails

- The user loses their recorded claim while the tokens remain stuck in the contract

*Round 1 | Agents: codex_1*

---

## Low (1)

### F-006: ETH-underlying exercise cannot span multiple vaults in one transaction

**Confidence:** high | **Locations:** `onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1491, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1509, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1816, onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol:1875`

`exercise()` can iterate across multiple vaults, but each internal `_exercise()` independently requires `msg.value == amtUnderlyingToPay`. Because `msg.value` is constant for the entire transaction, any ETH-underlying exercise that needs more than one vault reverts unless the user splits it into separate calls.

**Impact:** Fragmented vault debt makes the advertised multi-vault exercise path unusable for ETH-settled options. Users must race multiple transactions during the exercise window, increasing failure risk and potentially preventing full redemption under time pressure.

**Paths:**

- A holder needs to exercise against two or more vaults

- They call `exercise()` once with the full vault list and a total ETH payment

- The first `_exercise()` compares the unchanged transaction-wide `msg.value` to only its partial underlying amount

- The transaction reverts unless the holder manually splits the exercise into separate calls

*Round 1 | Agents: codex_1*

---
