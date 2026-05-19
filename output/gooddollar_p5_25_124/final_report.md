# Audit Report

**Total findings:** 5

## High (2)

### F-001: Governance rotation leaves former avatar with permanent reserve minting and helper admin powers

**Confidence:** high | **Locations:** `0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/GoodReserveCDai.sol:145, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/GoodReserveCDai.sol:148, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/GoodReserveCDai.sol:228, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/GoodReserveCDai.sol:348, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/DistributionHelper.sol:91, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/DistributionHelper.sol:216`

`GoodReserveCDai` and `DistributionHelper` snapshot the current `avatar` into `AccessControl` roles during initialization, but those roles are never revoked or automatically reassigned when `Controller.avatar()` changes. After governance rotation, the former avatar still keeps `RESERVE_MINTER_ROLE` on the reserve and `DEFAULT_ADMIN_ROLE` on the helper.

**Impact:** A stale governance key can continue minting G$ through `mintRewardFromRR` and can still reconfigure distribution recipients. Rotating governance therefore does not actually remove protocol control from the old avatar, enabling unauthorized inflation, value extraction, and long-lived control over where future distributions are sent.

**Paths:**

- DAO governance rotates `Controller.avatar()` to a new address

- The old avatar retains `RESERVE_MINTER_ROLE` in `GoodReserveCDai` and `DEFAULT_ADMIN_ROLE` in `DistributionHelper`

- The old avatar calls `mintRewardFromRR(...)` to mint G$ to itself and monetizes the new supply through the reserve/exchange flow

- The old avatar also calls `addOrUpdateRecipient(...)` to redirect future distributions

*Round 1 | Agents: codex_1*

---

### F-003: Anyone can trigger zero-slippage fee-restocking sales of protocol-owned G$

**Confidence:** high | **Locations:** `0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/DistributionHelper.sol:178, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/DistributionHelper.sol:184, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/DistributionHelper.sol:298, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/DistributionHelper.sol:304, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/ExchangeHelper.sol:185, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/ExchangeHelper.sol:234, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/ExchangeHelper.sol:335`

`DistributionHelper.onDistribution()` is publicly callable, and when the helper is short on native gas it calls `buyNativeWithGD()`, which routes through `ExchangeHelper.sell(path, amountToSell, 0, 0, ...)`. The reserve exit and the downstream DAI->ETH swap both accept zero minimum output, so the protocol will sell G$ for whatever price the market offers at the exact moment any caller triggers the refill.

**Impact:** MEV searchers can sandwich or otherwise manipulate the fee-restocking sale and extract value directly from protocol-owned G$ that should have gone to distribution recipients. Because anyone can trigger the sale whenever the ETH balance is low, this value loss is permissionless and repeatable.

**Paths:**

- The helper's ETH balance drops below `minBalanceForFees`

- An attacker manipulates or sandwiches the DAI/ETH route used during `ExchangeHelper.sell(...)`

- The attacker or any third party calls `onDistribution(...)`

- The helper sells protocol-owned G$ with `_minReturn = 0` and `_minTokenReturn = 0`, realizing a highly unfavorable execution price

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (3)

### F-002: Public address refresh makes the hardcoded guardian effectively irrevocable

**Confidence:** high | **Locations:** `0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/DistributionHelper.sol:96, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/DistributionHelper.sol:102, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/DistributionHelper.sol:103, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/DistributionHelper.sol:106`

`DistributionHelper.updateAddresses()` is public and unconditionally `_setupRole`s `GUARDIAN_ROLE` for the hardcoded EOA `0xE0c5...e7Ec`. Even if governance revokes that account, any caller can immediately restore its guardian privileges by calling `updateAddresses()`.

**Impact:** The hardcoded guardian remains a permanent backdoor into `setFeeSettings`. If that key is compromised, deprecated, or no longer trusted, it can still be reactivated permissionlessly and used to sabotage bridging or force economically harmful fee-restocking behavior.

**Paths:**

- Governance revokes `GUARDIAN_ROLE` from the hardcoded EOA

- Any external account calls `updateAddresses()`

- The hardcoded EOA is re-granted `GUARDIAN_ROLE`

- That guardian calls `setFeeSettings(...)` to block distributions or force unfavorable fee sales

*Round 1 | Agents: codex_1*

---

### F-004: Contract recipients can re-enter `onDistribution` during `transferAndCall`

**Confidence:** medium | **Locations:** `0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/DistributionHelper.sol:178, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/DistributionHelper.sol:193, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/DistributionHelper.sol:234, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/reserve/DistributionHelper.sol:272`

`DistributionHelper.onDistribution()` has no reentrancy guard and its `Contract` transfer path sends G$ with `transferAndCall(...)`, which can invoke arbitrary recipient code before the outer distribution loop finishes. A configured contract recipient can therefore call back into `onDistribution()` while the helper still holds the remainder of the current distribution balance.

**Impact:** A malicious or compromised contract recipient can recursively pull additional shares from the still-undistributed balance, and in many recipient orderings can also make the outer loop fail due to insufficient balance for later transfers. This can either overpay the attacking recipient or DoS all distributions.

**Paths:**

- A recipient is configured with `transferType == Contract`

- `onDistribution()` starts distributing the helper's full G$ balance

- `transferAndCall(...)` invokes the recipient's callback before the outer loop completes

- The recipient re-enters `onDistribution()` to consume remaining balance or leave later transfers unable to complete

*Round 1 | Agents: codex_1, opencode_1*

---

### F-005: Unchecked oracle answers can halt `collectInterest` and misprice keeper rewards

**Confidence:** high | **Locations:** `0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/staking/GoodFundManager.sol:463, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/staking/GoodFundManager.sol:470, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/staking/GoodFundManager.sol:475, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/staking/GoodFundManager.sol:477, 0xaacbaab8571cbeceb46ba85b5981efdb8928545e/contracts/staking/GoodFundManager.sol:491`

`GoodFundManager` uses `latestAnswer()` from the gas-price and DAI/ETH oracles directly, without checking freshness and without validating that the returned values are positive and non-zero before casting and dividing by them.

**Impact:** If either oracle serves a stale, zero, or negative answer, `collectInterest()` can revert outright or compute distorted gas reimbursement values. Because `collectInterest()` drives reserve interest collection and downstream UBI minting, bad oracle data can halt core distribution flows until the feed is corrected.

**Paths:**

- One of the Chainlink feeds returns stale, zero, or negative data

- `collectInterest()` calls `getGasPriceIncDAIorDAI()` / `getGasPriceInGD()`

- The code casts the signed answer to `uint256` and divides by the unchecked value

- The transaction reverts or uses a materially wrong keeper reward calculation

*Round 1 | Agents: codex_1, opencode_1*

---
