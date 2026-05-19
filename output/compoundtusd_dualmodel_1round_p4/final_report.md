# Audit Report

**Total findings:** 4

## High (4)

### F-001: Balance-delta accounting can over-credit deposits and repayments for mutable underlyings

**Confidence:** medium | **Locations:** `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CErc20.sol:161, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol:424, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol:672, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol:754, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol:1001`

`doTransferIn()` credits the caller with `balanceAfter - balanceBefore` instead of the payer's real economic debit. If the underlying can mint, positively rebase, or otherwise increase the cToken's balance during `transferFrom`, the returned amount is overstated and downstream mint/repay/liquidation/add-reserve accounting accepts that inflated value as if it had actually been paid by the caller.

**Impact:** A mutable or upgradeable underlying can mint unbacked cTokens, reduce debt for less than the nominal repayment, or inflate reserves/accounting. The resulting fake collateral or underpaid debt can be used to drain other markets or leave this market insolvent.

**Paths:**

- Underlying increases the cToken balance during `mint()` -> `actualMintAmount` is overstated -> caller receives excess cTokens backed by assets they did not truly supply

- Underlying increases the cToken balance during `repayBorrow()` / `repayBorrowBehalf()` / `liquidateBorrow()` -> `actualRepayAmount` is overstated -> borrower debt is erased by more than the liquidator or payer really transferred

- Underlying increases the cToken balance during `_addReserves()` -> reserves accounting rises without a matching real contribution from the caller

*Round 1 | Agents: codex_1*

---

### F-002: Live-balance exchange-rate accounting lets external balance increases inflate collateral value

**Confidence:** medium | **Locations:** `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CErc20.sol:147, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol:186, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol:293, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol:410`

`exchangeRateStoredInternal()` prices cTokens from the raw live underlying balance `balanceOf(address(this))`. Any unsolicited balance increase that does not mint matching cTokens—such as a positive rebase, issuer mint to the market, or other exogenous balance increase—immediately raises the exchange rate used in account snapshots and collateral checks.

**Impact:** If the underlying issuer or another actor can create or later reverse those balance increases, cToken holders can appear overcollateralized and borrow other assets against value that is not durably backed. Once the extra balance disappears or becomes unusable, the protocol is left with bad debt.

**Paths:**

- Attacker or issuer acquires some cTokens -> underlying balance of the market is increased externally without minting new cTokens -> `getAccountSnapshot()` reports a higher exchange rate -> attacker borrows against inflated collateral

- Issuer/admin mints underlying directly to the cToken address or triggers a positive rebase -> all existing cTokens become artificially more valuable in Comptroller collateral calculations without matching liability accounting

*Round 1 | Agents: codex_1*

---

### F-003: Negative underlying balance changes can underflow exchange-rate math and freeze the market

**Confidence:** medium | **Locations:** `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CErc20.sol:147, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol:186, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol:293, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol:410, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol:480`

`exchangeRateStoredInternal()` computes `totalCash + totalBorrows - totalReserves` using checked arithmetic and derives `totalCash` from the live token balance. If the underlying balance is externally reduced below the protocol's accounting—for example by a negative rebase, clawback, confiscation, forced burn, or blacklist wipe—the subtraction underflows and reverts.

**Impact:** Once this happens, core reads and state transitions that depend on the exchange rate can revert indefinitely. That can block account snapshots, Comptroller liquidity checks, minting, redeeming, and other flows, leaving suppliers trapped and the market effectively bricked.

**Paths:**

- Underlying issuer/admin reduces the market's token balance below `totalReserves - totalBorrows` adjusted cash expectations -> `exchangeRateStoredInternal()` reverts -> `getAccountSnapshot()` and collateral checks start failing

- After an external cash loss, any path that consults the exchange rate, including `mint()` and `redeem*()`, becomes unusable and the market cannot recover without outside intervention

*Round 1 | Agents: codex_1*

---

### F-004: Underlying transfer controls can permanently lock redemptions, borrows, repayments, and liquidations

**Confidence:** medium | **Locations:** `0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CErc20.sol:161, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CErc20.sol:198, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol:541, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol:609, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol:672, 0x3363bae2fc44da742df13cd3ee94b6bb868ea376/contracts/CToken.sol:754`

All user exits and debt-management flows depend on the underlying continuing to allow `transferFrom` into the market and `transfer` out of the market. There is no fallback or escape hatch if the underlying token blacklists the cToken, pauses transfers, or censors particular senders/recipients.

**Impact:** A centrally controlled or censorable underlying can turn a token-level freeze into a protocol-level lockup: suppliers may be unable to redeem, borrowers may be unable to borrow or repay, and liquidations may stop working, causing stuck funds and potentially unliquidatable bad debt.

**Paths:**

- Underlying blacklists or pauses the cToken address -> `doTransferIn()` and/or `doTransferOut()` revert -> mint, redeem, borrow, repay, and liquidation flows fail

- Underlying censors specific users or recipients -> affected accounts cannot receive redemptions/borrows or submit repayments, while unhealthy positions become hard or impossible to liquidate cleanly

*Round 1 | Agents: codex_1*

---
