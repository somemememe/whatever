# Audit Report

**Total findings:** 5

## High (2)

### F-001: Existing-loan wrapper authorization depends on caller-supplied borrower/trader values

**Confidence:** low | **Locations:** `onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1594, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1605, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1647, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1658`

When `loanId != 0`, `_borrow` and `_marginTrade` only require `msg.sender == borrower` or `msg.sender == trader`, but those addresses are taken directly from user input and then forwarded in `sentAddresses` instead of being derived from an authoritative on-chain loan record.

**Impact:** If the downstream `borrowOrTradeFromPool` path does not independently re-check the stored loan owner/trader for an existing `loanId`, an attacker can supply their own address as `borrower`/`trader` together with a victim loan ID and operate on someone else's position, potentially refinancing it, changing terms, or extracting value.

**Paths:**

- Call `borrow(victimLoanId, ..., borrower=attacker, receiver=attacker, ...)`; the wrapper authorization passes because it compares `msg.sender` to the attacker-supplied `borrower`.

- Call `marginTrade(victimLoanId, ..., trader=attacker, ...)`; the wrapper forwards attacker-controlled `sentAddresses[1]`/`sentAddresses[2]` for an existing loan.

*Round 1 | Agents: codex_1*

---

### F-002: Nominal-amount accounting overcredits deposits and collateral for fee-on-transfer assets

**Confidence:** medium | **Locations:** `onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1522, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1528, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1537, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1712, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1728, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1869, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1875, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1880, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:2293, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:2303`

`_mintToken`, `_totalDeposit`, and both `_verifyTransfers` variants use user-declared amounts (`depositAmount`, `loanTokenSent`, `collateralTokenSent`) for minting and downstream loan accounting, but they never measure the actual token balance delta received after `transferFrom`.

**Impact:** If any supported asset is deflationary, fee-on-transfer, or otherwise delivers less than the nominal amount, lenders can receive too many pool shares for too little underlying and borrowers can open or top up positions with less real collateral/funding than the accounting assumes, creating dilution, bad debt, or pool insolvency.

**Paths:**

- Deposit a fee-on-transfer `loanTokenAddress` via `mint`; shares are minted from `depositAmount` even if the pool receives less.

- Open `borrow` or `marginTrade` using a fee-on-transfer collateral token or loan token contribution; `sentAmounts` still report the pre-fee amount to `bZxContract`.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-003: iToken transfers can be globally frozen by an external interest-query failure

**Confidence:** high | **Locations:** `onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1150, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1175, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1268, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:2074`

Both `transfer` and `transferFrom` route through `_internalTransferFrom`, which always calls `tokenPrice()`. `tokenPrice()` in turn calls `bZxContract.getLenderInterestData` whenever `lastSettleTime_` differs from the current timestamp, so a revert or outage in that external dependency makes plain ERC20 transfers revert too.

**Impact:** A failure, pause, upgrade bug, or gas griefing issue in the external protocol can freeze all iToken transfers and integrations that rely on moving iTokens, producing a protocol-wide denial of service for holders.

**Paths:**

- Make `bZxContract.getLenderInterestData(address(this), loanTokenAddress)` revert in a block where `lastSettleTime_ != block.timestamp`; any subsequent `transfer` or `transferFrom` reverts via `tokenPrice()`.

*Round 1 | Agents: codex_1*

---

## Low (2)

### F-004: marginTrade forwards undeclared excess ETH downstream

**Confidence:** medium | **Locations:** `onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1647, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1790, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1821, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1858, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:1873, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:2278, onchain_auto/0x9e1341a201b1aecb1b0dd584989790a0232b4af5/Contract.sol:2301`

Unlike `_borrow`, `_marginTrade` does not constrain `msg.value` to the declared collateral or loan-token contribution. `_verifyTransfers` starts from `msgValue = msg.value`, subtracts only the portion it explicitly wraps, and then forwards any leftover native ETH to `borrowOrTradeFromPool` even though `sentAmounts` only track the declared token amounts.

**Impact:** Users can accidentally donate ETH, and downstream accounting may receive native ETH that is not reflected in the wrapper's token-side bookkeeping, creating mismatches and hard-to-audit edge cases around position funding.

**Paths:**

- Call `marginTrade` in the standard path with `msg.value > collateralTokenSent`; only `collateralTokenSent` is wrapped, and the remainder is forwarded as raw ETH.

- Call WETH `marginTrade` with `msg.value > loanTokenSent`; only `loanTokenSent` is wrapped into WETH and the leftover ETH is forwarded separately.

*Round 1 | Agents: codex_1*

---

### F-005: Proxy silently accepts low-gas ETH transfers and can trap native ETH

**Confidence:** high | **Locations:** `onchain_auto/0xb983e01458529665007ff7e0cddecdb74b967eb6/Contract.sol:624, onchain_auto/0xb983e01458529665007ff7e0cddecdb74b967eb6/Contract.sol:628, onchain_auto/0xb983e01458529665007ff7e0cddecdb74b967eb6/Contract.sol:629`

The proxy fallback returns successfully when `gasleft() <= 2300` instead of reverting or forwarding the call to logic. As a result, Solidity `transfer`/`send` can deliver ETH to the proxy without invoking any wrapping or accounting logic.

**Impact:** Native ETH can become stuck or operationally orphaned in the proxy, and integrations may incorrectly assume a successful low-gas ETH transfer was meaningfully processed by the protocol.

**Paths:**

- Send ETH to the proxy using Solidity `transfer` or `send`; the fallback returns early and the ETH stays on the proxy balance.

*Round 1 | Agents: codex_1*

---
