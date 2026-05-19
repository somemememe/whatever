# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: Anyone can reinitialize the NFT contracts and seize deposit/funding token ownership

**Confidence:** high | **Locations:** `onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/NFT.sol:39, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/NFT.sol:44, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/NFT.sol:79, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/NFT.sol:83, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:770, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:903, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterestWithDepositFee.sol:801, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterestWithDepositFee.sol:934`

`NFT.init()` is external and has neither a one-time initialization guard nor access control, so any account can call it on an already-deployed deposit or funding NFT clone and transfer contract ownership to itself. The new owner then gains the owner-only `mint`/`burn` powers over the live position NFTs relied on by the pools.

**Impact:** An attacker can take over a pool's `depositNFT` or `fundingNFT`, burn users' position tokens, block future minting, and break the ownership checks used during withdrawals and funder payouts. This can permanently lock depositor and funder claims and DoS the pool.

**Paths:**

- Call `NFT.init(attacker, ...)` on the deployed deposit NFT or funding NFT contract.

- As the new owner, call `burn(tokenId)` on victim deposit/funding NFTs or interfere with future minting.

- Victim `withdraw()` / funder payout paths revert when `ownerOf()` no longer returns a valid holder for the expected NFT.

*Round 1 | Agents: codex_1*

---

## High (2)

### F-002: Vested MPH rewards can make depositor withdrawals impossible unless users source extra MPH

**Confidence:** high | **Locations:** `onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/MPHMinter.sol:105, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/MPHMinter.sol:113, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/rewards/MPHMinter.sol:154, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:777, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterestWithDepositFee.sol:809, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/models/issuance/MPHIssuanceModel01.sol:121, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/models/issuance/MPHIssuanceModel01.sol:123`

When depositor rewards are vested, `mintDepositorReward()` mints MPH to `MPHMinter` and escrows it in `Vesting`, but every withdrawal still calls `takeBackDepositorReward()`, which unconditionally pulls MPH from the withdrawer's wallet via `mph.transferFrom(from, ...)` instead of canceling or netting against the user's vest. Early withdrawals always require the full reward back, and mature withdrawals can also require liquid MPH when the take-back multiplier is nonzero.

**Impact:** Depositors can be unable to withdraw principal unless they separately acquire liquid MPH and approve the minter. With vesting enabled, this creates a realistic principal lockup / forced-buy scenario for ordinary users; even without vesting, users who no longer hold the rewarded MPH can be blocked from withdrawing when clawback is required.

**Paths:**

- Configure a pool with a nonzero depositor reward vesting period.

- User deposits; the MPH reward is vested into `Vesting` instead of transferred to the user's wallet.

- User later withdraws; the pool calls `takeBackDepositorReward(user, ...)`.

- `MPHMinter` executes `mph.transferFrom(user, ...)`, which reverts unless the user separately holds enough liquid MPH and has approved the minter.

*Round 1 | Agents: codex_1*

---

### F-003: `fundMultiple()` can charge new funders for stale deficits from already-withdrawn deposits that carry no recoverable claim

**Confidence:** high | **Locations:** `onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:317, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:320, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:335, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:488, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:817, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterest.sol:856, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterestWithDepositFee.sol:320, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterestWithDepositFee.sol:338, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/DInterestWithDepositFee.sol:887`

`fundMultiple()` adds `finalSurplusAmount` from inactive deposits into `totalDeficit`, but only active deposits contribute to `recordedFundedDepositAmount`. After an unfunded deposit is withdrawn, its stored negative surplus can therefore still be charged to later funders even though no active deposit remains for that funding to attach to or earn back from.

**Impact:** Later funders can pay capital to recapitalize stale losses with no corresponding funded position or recoverable claim. That portion of the funding NFT is economically worthless, allowing phantom deficits from already-withdrawn deposits to be socialized onto new funders and directly destroying funder principal.

**Paths:**

- Create an unfunded deposit and withdraw it before it is funded.

- The pool records the withdrawn deposit's negative `finalSurplusAmount`.

- A later caller invokes `fundMultiple()` over a range that includes that inactive deposit.

- `totalDeficit` includes the inactive deposit's stored deficit, but `recordedFundedDepositAmount` only includes still-active deposits.

- The funder pays the larger deficit amount while receiving a claim only on the smaller active-deposit set.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-004: Zero-coupon bond redemption is first-come-first-served instead of pro-rata when collateral is short

**Confidence:** high | **Locations:** `onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/fractionals/ZeroCouponBond.sol:169, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/fractionals/ZeroCouponBond.sol:170, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/fractionals/ZeroCouponBond.sol:175, onchain_auto/0xf0b7de03134857391d8d43ed48e20edf21461097/contracts/fractionals/ZeroCouponBond.sol:178`

`redeemStablecoin()` redeems `min(amount, stablecoinBalance)` and burns only that many bonds, without scaling payouts by `stablecoinBalance / totalSupply()`. If a bond series is undercollateralized at maturity, early redeemers still exit at par until the stablecoin balance is exhausted.

**Impact:** When stablecoin backing is insufficient, early redeemers can drain the remaining collateral 1:1 and leave later bondholders with a disproportionate loss. This creates a bank-run dynamic and unfairly reallocates insolvency losses to slower redeemers.

**Paths:**

- Wait until maturity when `stablecoin.balanceOf(address(this)) < totalSupply()`.

- Redeem a large amount of ZCB early via `redeemStablecoin(amount)`.

- The function transfers up to the full current stablecoin balance at 1 bond : 1 stablecoin until the contract is emptied.

- Remaining bondholders are left with little or no collateral backing their outstanding bonds.

*Round 1 | Agents: codex_1*

---
