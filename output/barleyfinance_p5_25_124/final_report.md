# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: Unrestricted first-time referral initialization lets an attacker seize reward routing and brick reward-dependent share updates

**Confidence:** high | **Locations:** `0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:64, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:65, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:68, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:223, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/StakingPoolToken.sol:92, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/StakingPoolToken.sol:96`

`TokenRewards.updateReferral()` has no trusted initializer: while `referral` is unset, any address can install an arbitrary referral contract. All later reward distribution and future referral updates blindly trust that contract for `getRelationsREF()` and `owner()`.

**Impact:** The first caller can permanently take control of referral routing. A malicious referral contract can divert the referral share from every future reward payout, or simply revert in `getRelationsREF()` so `claimReward()` and any staking-share update that tries to distribute accrued rewards reverts. Because `StakingPoolToken` calls `setShares()` on transfer and unstake, users with pending rewards can be prevented from transferring staking receipts or unstaking LP positions until the attacker-controlled referral contract is replaced, which the attacker can also block by returning an attacker-controlled `owner()`.

**Paths:**

- Call `TokenRewards.updateReferral(maliciousReferral)` before the intended referral contract is set.

- Have `maliciousReferral.owner()` resolve to an attacker-controlled address so later `updateReferral()` calls stay under attacker control.

- Either return attacker-controlled referrers from `getRelationsREF()` to siphon referral payouts, or make `getRelationsREF()` revert so `claimReward()` and reward-triggering share updates fail.

*Round 1 | Agents: codex_1, opencode_1*

---

## High (1)

### F-002: Anyone can front-run a user’s first claim and permanently bind attacker-controlled referrers

**Confidence:** high | **Locations:** `0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:279, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:280, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:281, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:283`

`claimReward(address _wallet, address _referrer)` does not require `_wallet == msg.sender`. If the wallet has not been initialized in the referral system yet, any caller can make `TokenRewards` execute `referral.setReferral(_referrer, _wallet)` on the victim’s behalf.

**Impact:** An attacker can front-run a victim’s first reward claim and permanently assign attacker-controlled referral addresses to that victim. This diverts the protocol’s referral share from all future reward distributions for the victim without needing control of the victim wallet.

**Paths:**

- Wait until the referral contract has been configured and identify a staker whose referral entry is still unset.

- Front-run the victim’s first reward claim with `claimReward(victim, attackerReferrer)`.

- Subsequent reward distributions for that victim route the referral share to the attacker-controlled referral tree.

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-003: Dust supply causes the automatic fee path to execute a zero-input swap and can freeze transfers/sells

**Confidence:** medium | **Locations:** `0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/DecentralizedIndex.sol:94, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/DecentralizedIndex.sol:96, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/DecentralizedIndex.sol:97, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/DecentralizedIndex.sol:99, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/DecentralizedIndex.sol:108, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/DecentralizedIndex.sol:114`

The transfer hook computes `_min = totalSupply() / 10000`. Once total supply falls below 10,000 base units, `_min` becomes zero, so every eligible transfer from a non-pool address enters `_feeSwap(0)` whenever the pool still has liquidity.

**Impact:** Standard Uniswap V2 swap paths are not designed for zero-input swaps, so remaining holders can become unable to transfer tokens or sell into the pool once supply has been debonded down to dust while fee tokens remain on the contract. This is a permissionless liveness failure for the residual supply.

**Paths:**

- Debond or burn supply until `totalSupply() < 10000` base units while the V2 pool still has liquidity and the index contract still holds fee tokens.

- Trigger any transfer or sale from a non-pool address.

- The transfer hook calls `_feeSwap(0)`, causing the transfer path to revert instead of no-oping.

*Round 1 | Agents: codex_1*

---

### F-004: Repeated failed reward swaps can wrap slippage math and strand protocol DAI fees

**Confidence:** low | **Locations:** `0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:40, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:154, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:163, 0x04c80bb477890f3021f03b068238836ee20aa0b8/contracts/TokenRewards.sol:175`

Each failed `exactInputSingle()` increments `_rewardsSwapSlippage` by 10, and Solidity 0.7 performs the later `(1000 - _rewardsSwapSlippage)` arithmetic without underflow checks. If enough failures accumulate, the minimum-out calculation wraps instead of clamping or reverting.

**Impact:** If an attacker can keep `depositFromDAI()` failing while the rewards contract holds DAI, the slippage guard eventually becomes nonsensical. At that point DAI-to-reward conversions can become unreliable or keep reverting, causing protocol DAI fees and flash-loan fees to accumulate in `TokenRewards` instead of being converted into distributable staking rewards until a successful swap resets the counter.

**Paths:**

- Ensure `TokenRewards` holds DAI and that `exactInputSingle()` keeps failing for repeated `depositFromDAI(0)` calls.

- Repeat failed calls until `_rewardsSwapSlippage` exceeds 1000.

- Future `amountOutMinimum` calculations wrap, making reward-token conversion unreliable and potentially stranding DAI fees in the rewards contract.

*Round 1 | Agents: codex_1*

---
