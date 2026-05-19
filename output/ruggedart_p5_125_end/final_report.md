# Audit Report

**Total findings:** 7

## Critical (1)

### F-003: Any user can buy staked NFTs out of the shared pool at a fixed 1.1-token price

**Confidence:** high | **Locations:** `0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:177, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:182, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:244, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:253, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:258`

`stakeNFTs()` transfers token IDs into the market contract, but the contract never records who deposited which NFT or marks them as non-sale inventory. `targetedPurchase()` later lets any caller specify arbitrary token IDs and pulls those IDs out of the contract for a flat `1.1 ether` each via `_targetedPurchase()`. That means freshly staked NFTs become immediately purchasable by anyone, regardless of the original owner’s intent.

**Impact:** A buyer can monitor for rare or valuable NFTs being staked and immediately extract them from the pool for the floor price, capturing the full rarity premium and leaving the original staker with only a fungible claim.

**Paths:**

- Victim calls `stakeNFTs([rareTokenId])` and transfers the NFT into the market contract.

- Attacker calls `targetedPurchase([rareTokenId])` and acquires that specific NFT for `1.1 ether` worth of Rugged.

- Victim can no longer recover the original NFT and is left with only the protocol’s fungible accounting claim.

*Round 1 | Agents: codex_1*

---

## High (4)

### F-002: NFT staking destroys asset identity and only returns a fungible balance claim

**Confidence:** high | **Locations:** `0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:177, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:194, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:201, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:215`

`stakeNFTs()` converts each deposited token ID into `1 ether` of `amountStaked`, but it does not store the deposited IDs or associate them with the depositor. `unstake()` later returns only fungible Rugged amounts, never the original NFTs. The staking flow therefore irreversibly turns unique NFTs into generic balance accounting.

**Impact:** Users who stake rare NFTs permanently give up the specific token they deposited and can only exit with fungible value. Any rarity premium or collectible value is lost even if no attacker intervenes.

**Paths:**

- User deposits a valuable NFT through `stakeNFTs([tokenId])`.

- Contract credits `amountStaked += 1 ether` but stores no ownership record for that NFT.

- User later exits through `unstake(1 ether)` and receives fungible Rugged rather than the original token ID.

*Round 1 | Agents: codex_1*

---

### F-004: Rugged transfers are never validated, so failed or short transfers can desynchronize market accounting

**Confidence:** medium | **Locations:** `0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:116, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:160, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:168, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:182, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:191, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:211, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:227, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:245, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:258`

The market assumes every Rugged transfer succeeds in full, but it never validates return values or balance deltas. `IRugged.transferFrom` is declared with no return value, so false-returning ERC20-style implementations would be treated as success, and `transfer` return values are ignored entirely. As a result, incentives can be recorded without being funded, deposits can be overcredited if less than the nominal amount arrives, and reward/unstake payouts can silently fail while user accounting is still advanced.

**Impact:** If Rugged is fee-on-transfer, short-transferring, false-returning, or otherwise non-standard, the market can become undercollateralized or distribute unfunded rewards. Attackers or users can obtain full staking or purchase credit while the contract receives less than it accounts for, and legitimate stakers can lose rewards if outgoing transfers fail silently.

**Paths:**

- Owner calls `addIncentive(...)`; the contract records the incentive before/without confirming that `_rewardTotal` actually arrived.

- User stakes via `stake()` or `stakeNFTs()`; the contract credits the nominal amount even if Rugged transfers less than expected.

- Buyer calls `targetedPurchase()`; the market may release NFTs even though the purchase payment transferred in short.

- User calls `claimReward()` or `unstake()`; Rugged transfer can fail silently while `rewardDebt` or stake balances are still updated.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-006: The unbounded incentives array can eventually gas-DoS staking, claiming, and withdrawals

**Confidence:** high | **Locations:** `0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:100, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:121, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:133, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:155, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:177, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:201, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:220`

Every state-changing staking action calls `updatePool()`, which calls `calculateReward()`, which loops over the entire `incentives` array. Incentives are only appended and are never pruned, compacted, or checkpointed into a bounded structure. Over time, the gas cost of `stake()`, `stakeNFTs()`, `unstake()`, and `claimReward()` grows linearly with historical incentives.

**Impact:** Once enough incentives have been added, core user flows can exceed the block gas limit and become uncallable, locking staked positions and preventing reward claims or withdrawals.

**Paths:**

- The owner repeatedly funds incentives over the lifetime of the protocol.

- Users later call `claimReward()` or `unstake()` after the array has grown large.

- `calculateReward()` iterates across too many historical entries and the transaction runs out of gas, preventing exit.

*Round 1 | Agents: codex_1*

---

### F-001: Missing lower-bound token ID validation may allow zero-ID free staking

**Confidence:** low | **Locations:** `0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:177, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:179, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:182, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:194`

`stakeNFTs()` only rejects token IDs greater than `10_000`; it does not reject `0`. If the Rugged token uses 1-based NFT IDs, or if `transferFrom(..., 0)` is treated as a zero-value/no-op transfer instead of a real NFT move, a caller can submit zero entries and still receive `1 ether` of stake credit per entry.

**Impact:** Under a 1-based or zero-no-op Rugged implementation, an attacker could mint stake without depositing real NFTs, then drain incentive rewards and potentially withdraw Rugged backed by honest users.

**Paths:**

- Attacker calls `stakeNFTs([0,0,...])`.

- Each zero entry passes validation and contributes to `_tokenIds.length * 1 ether` stake credit.

- Attacker later calls `claimReward()` and/or `unstake()` against stake that may not be backed by actual NFTs.

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-005: Successful swap purchases can strand refunded or unused ETH in the market contract

**Confidence:** high | **Locations:** `0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:264, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:267, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:277, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:291`

The payable `targetedPurchase(..., swapParam)` forwards the caller’s entire `msg.value` to the Universal Router. If the router consumes only part of that ETH and refunds the remainder, the refund comes back to `receive()`, which accepts ETH only from the router and stores it on the market contract. There is no logic to return refunded ETH to the buyer and no withdrawal path for trapped ETH.

**Impact:** Users can permanently lose leftover ETH from overpayment, partial fills, or routes that do not spend the full forwarded amount.

**Paths:**

- User calls `targetedPurchase(tokenIds, swapParam)` with more ETH than the router ultimately spends.

- Universal Router refunds the unused ETH back to the market contract.

- The purchase completes, but the refunded ETH remains trapped because the contract has no refund or rescue function.

*Round 1 | Agents: codex_1*

---

### F-008: Incentives that elapse while nobody is staked become permanently stranded

**Confidence:** high | **Locations:** `0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:100, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:121, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:123, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:137, 0xfe380fe1db07e531e3519b9ae3ea9f7888ce20c6/src/Market.sol:145`

When `totalStaked == 0`, `updatePool()` does not accrue any incentive rewards and instead simply sets `lastUpdateTime = block.timestamp`. If an incentive interval passes during a zero-stake period, the elapsed portion is skipped forever rather than being preserved or recoverable later. Because there is no owner rescue or incentive-cancellation path, undistributed reward tokens remain stuck in the contract.

**Impact:** Reward sponsors can permanently lose part or all of funded incentives, and advertised emissions can silently fail to reach future stakers. The stranded Rugged balance cannot be withdrawn or redistributed through any explicit mechanism.

**Paths:**

- Owner funds an incentive with `addIncentive(...)` while no one is staked.

- Time passes through part or all of the incentive window before any user stakes.

- A later `updatePool()` call overwrites `lastUpdateTime`, skipping the elapsed rewards and leaving part of `rewardTotal` permanently undistributed in the contract.

*Round 1 | Agents: merge_review*

---
