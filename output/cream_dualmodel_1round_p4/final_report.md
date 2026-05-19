# Audit Report

**Total findings:** 2

## High (1)

### F-001: Collateral cap is unenforceable for pre-upgrade balances in upgraded collateral-cap markets

**Confidence:** high | **Locations:** `0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CCollateralCapErc20CheckRepayDelegate.sol:31, 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CCollateralCapErc20CheckRepay.sol:311, 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CCollateralCapErc20CheckRepay.sol:314, 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CCollateralCapErc20CheckRepay.sol:491, 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CCollateralCapErc20CheckRepay.sol:506`

When a live market is upgraded to `CCollateralCapErc20CheckRepayDelegate`, `_becomeImplementation` initializes `internalCash` but does not backfill `totalCollateralTokens` or per-user collateral state. Uninitialized legacy accounts still have their full `accountTokens` counted by `getCTokenBalanceInternal`, but are omitted from `totalCollateralTokens`. Later, `initializeAccountCollateralTokens` copies a legacy member's entire historical balance into `accountCollateralTokens` and adds it to `totalCollateralTokens` without enforcing `collateralCap`, whereas only fresh collateral growth through `increaseUserCollateralInternal` is cap-checked.

**Impact:** Governance cannot rely on the configured collateral cap after upgrading an already-live market. Legacy suppliers can continue using uncapped balances as collateral, and once they touch the market those balances are backfilled into collateral accounting without any cap enforcement. This defeats the intended market-wide collateral limit and can let the protocol support materially more borrowable collateral than intended, increasing insolvency and bad-debt risk.

**Paths:**

- Upgrade an existing live `CErc20Delegator` market to the collateral-cap implementation.

- Because `_becomeImplementation` does not migrate collateral accounting, `totalCollateralTokens` starts below actual collateral usage while legacy balances still count in account snapshots.

- A pre-upgrade supplier later mints, redeems, transfers, or is involved in a seizure, triggering `initializeAccountCollateralTokens`.

- That function credits the account's full legacy balance as collateral and increments `totalCollateralTokens` without applying the configured `collateralCap`.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-002: Flash-loan callers can spoof the `initiator` value delivered to receivers

**Confidence:** medium | **Locations:** `0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CCollateralCapErc20CheckRepay.sol:186, 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/CCollateralCapErc20CheckRepay.sol:219, 0x96cc0f947b6c8f4675159ea03144f8c17d5a2fc8/contracts/ERC3156FlashBorrowerInterface.sol:6`

`flashLoan` accepts an arbitrary `initiator` argument from the external caller and forwards it to `receiver.onFlashLoan(...)` instead of deriving the initiator from `msg.sender`. Because the callback interface documents `initiator` as the loan initiator, receivers that trust this field for authorization can be tricked by any caller that supplies a spoofed trusted address.

**Impact:** Integrated flash-loan receivers can be induced to execute privileged logic for an attacker if they gate behavior on the `initiator` value they receive in `onFlashLoan`. This can lead to unauthorized strategy execution or asset movement in downstream integrations that assume standard initiator semantics.

**Paths:**

- A receiver contract implements `onFlashLoan` and authorizes sensitive behavior when `initiator` equals a trusted address.

- An attacker calls `flashLoan(receiver, trustedAddress, amount, data)`.

- The lender forwards `trustedAddress` to the receiver even though the attacker initiated the transaction.

- The receiver misattributes the flash loan to the trusted address and executes the privileged path for the attacker.

*Round 1 | Agents: codex_1*

---
