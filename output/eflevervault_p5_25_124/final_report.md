# Audit Report

**Total findings:** 5

## Critical (3)

### F-001: Anyone can invoke the Balancer callback and force arbitrary leveraging or deleveraging

**Confidence:** high | **Locations:** `onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:306, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:312, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:317, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:320, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:382, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:436`

`receiveFlashLoan()` only checks `msg.sender == balancer` and the raw `userData` bytes, but never verifies that this vault initiated the flash loan or that a flash-loan operation is currently expected. Because Balancer flash loans are permissionless, any external account can ask Balancer to call this vault with `userData = "0x1"` or `"0x2"` and force `_deposit()` or `_withdraw()` against the vault's live position.

**Impact:** A permissionless attacker can repeatedly rebalance the vault without consent, paying flash-loan fees out of shared equity, forcing unexpected leverage changes, stranding large amounts of ETH on the contract while the vault remains unpaused, or even re-levering paused funds back into Aave. This breaks the vault's trust model and can drive material fund loss, insolvency, or set up the direct theft paths described below.

**Paths:**

- Attacker calls Balancer `flashLoan(recipient = vault, token = WETH, amount = chosenAmount, userData = "0x1")` to force `_deposit()`

- Or attacker calls Balancer `flashLoan(recipient = vault, token = WETH, amount <= getDebt(), userData = "0x2")` to force `_withdraw()`

- Balancer invokes `receiveFlashLoan()` on the vault

- Vault executes the requested rebalance even though no vault function initiated it

*Round 1 | Agents: codex_1*

---

### F-002: Idle ETH is excluded from NAV, so deposits can mint massively underpriced shares

**Confidence:** high | **Locations:** `onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:331, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:340, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:355, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:376, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:382, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:385`

When `is_paused == false`, `getCollecteral()` returns only Aave collateral and ignores ETH already held by the vault. `deposit()` therefore prices shares from `volume_before = getVolume()` without counting idle ETH, but `_deposit()` later converts the entire `address(this).balance` into new collateral. Any ETH already sitting on the contract is excluded from share pricing yet included in the depositor's assets.

**Impact:** If ETH is stranded on the contract while the vault is still unpaused, a depositor can mint shares against an artificially low NAV and capture most or all of that pre-existing equity. This is a direct theft vector, not merely accounting drift.

**Paths:**

- ETH accumulates on the vault while `is_paused == false` via unauthorized `_withdraw()`, accidental transfers, or forced ETH delivery

- Attacker calls `deposit()` with a small amount

- `volume_before` ignores the stranded ETH, so the attacker receives too many `ef_token` shares

- `_deposit()` sweeps both the attacker deposit and the pre-existing ETH into collateral, making the previously uncounted value belong to the attacker's newly minted shares

*Round 1 | Agents: codex_1*

---

### F-003: Unpaused withdrawals transfer the vault's entire ETH balance to the caller

**Confidence:** high | **Locations:** `onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:403, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:415, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:423, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:425, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:426`

In the unpaused branch, `withdraw()` correctly computes only a proportional flash-loan amount from the caller's share count, but after the flash-loan unwind it sets `to_send = address(this).balance` and transfers the vault's entire ETH balance to the withdrawing user. The payout is not limited to the ETH attributable to `_amount` shares.

**Impact:** Any shareholder can steal all ETH currently sitting in the vault, even if that ETH belongs to every holder. A tiny shareholder can therefore drain the full idle ETH balance created by unsolicited flash-loan callbacks, accidental transfers, or any other leftover ETH, making this a full-funds theft path once ETH is present on the contract.

**Paths:**

- ETH accumulates on the vault while it is unpaused

- Attacker acquires or already holds a small amount of `ef_token`

- Attacker calls `withdraw(smallAmount)`

- The function transfers all of `address(this).balance` to the attacker and burns only the small share amount

*Round 1 | Agents: codex_1, opencode_1*

---

## High (2)

### F-004: All Curve swaps use `min_dy = 0`, enabling sandwich extraction and arbitrary bad execution

**Confidence:** medium | **Locations:** `onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:389, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:446, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:527`

Every stETH/ETH Curve trade is executed with `min_dy = 0`, so the vault accepts any output amount. A searcher can manipulate the pool price immediately before a deposit, withdrawal, pause, or LTV rebalance and make the vault trade at a highly unfavorable rate.

**Impact:** Victim deposits, withdrawals, and owner rebalances can lose a large fraction of value to sandwich attacks or temporary pool distortions. Because the vault is leveraged, even modest price manipulation can materially damage equity.

**Paths:**

- Victim calls `deposit()` or `withdraw()`, or owner calls `pause()` / `raiseActualLTV()`

- Attacker front-runs by skewing the stETH/ETH Curve pool

- Vault executes `exchange(..., 0)` and accepts the manipulated output

- Attacker back-runs to restore the pool and realize profit from the vault's loss

*Round 1 | Agents: codex_1, opencode_1*

---

### F-005: Withdrawals and emergency pause can become impossible during a stETH depeg or severe pool illiquidity

**Confidence:** medium | **Locations:** `onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:415, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:436, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:446, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:448, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:453, onchain_auto/0xe39fd820b58f83205db1d9225f28105971c3d309/Contract.sol:463`

The withdrawal logic assumes that the proportional amount of withdrawn stETH can always be swapped back into at least `amount + fee_amount` ETH in the same transaction. If stETH trades far enough below ETH or Curve liquidity is too poor, `_withdraw()` will not have enough ETH to wrap and repay the flash loan, so the whole transaction reverts. `pause()` uses the same `_withdraw()` path and inherits the failure mode.

**Impact:** During market stress, ordinary withdrawals and even the owner's emergency `pause()` escape hatch can fail exactly when users most need to exit. This creates a realistic protocol-wide lockup and liquidation risk under adverse market conditions.

**Paths:**

- stETH trades at a deep discount or Curve liquidity becomes insufficient

- User calls `withdraw()` or owner calls `pause()`

- `_withdraw()` cannot obtain enough ETH to cover `amount + fee_amount`

- Flash-loan repayment fails and the transaction reverts

*Round 1 | Agents: codex_1*

---
