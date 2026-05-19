# Audit Report

**Total findings:** 5

## Critical (1)

### F-002: Owner backdoor can reassign any user's locked assets to an arbitrary recipient

**Confidence:** high | **Locations:** `onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:963, onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:983, onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:990, onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:998`

`recoverAssets()` is an owner-only function that iterates over every deposit assigned to an arbitrary `user`, rewrites each deposit's `withdrawalAddress` to `newRecipient`, moves the accounting balances, appends the deposit ids to the new recipient, and burns any lock NFTs. No proof of user consent or lost-wallet recovery authorization is required.

**Impact:** A malicious or compromised owner can seize all ERC20 and NFT locks from any user. Matured positions can be withdrawn immediately, and unmatured positions are effectively confiscated until unlock.

**Paths:**

- Owner calls `recoverAssets(victim, attacker)`

- The contract rewrites all of the victim's deposit ownership to `attacker` and clears `depositsByWithdrawalAddress[victim]`

- The attacker withdraws matured assets immediately or waits until unlock for the rest

*Round 1 | Agents: codex_1, opencode_1*

---

## High (1)

### F-001: Uninitialized proxy deployment can be seized by the first caller

**Confidence:** medium | **Locations:** `onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:119, onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:125, onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/node_modules/@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol:31, onchain_auto/0xe2fe530c047f2d85298b07d9333c05737f1435fb/Contract.sol:185`

`LockToken.initialize()` is externally callable and ultimately executes `__Ownable_init_unchained()`, which sets ownership to `msg.sender`. The bundled proxy constructor explicitly allows deployment with empty init calldata, so if the proxy is ever deployed or upgraded without atomically calling `initialize()`, any third party can claim ownership first.

**Impact:** The first caller can take full admin control of the locker, then pause the system, alter fee/NFT settings, whitelist accounts, and invoke `recoverAssets()` to redirect users' locked positions.

**Paths:**

- Deploy or upgrade the proxy without initialization calldata

- An attacker calls `initialize()` before the intended admin does

- The attacker becomes owner and exercises privileged functions such as `pause()`, `setFeeParams()`, or `recoverAssets()`

*Round 1 | Agents: codex_1*

---

## Medium (3)

### F-003: Arbitrary-recipient dust locks can bloat a victim's deposit list and make some exits gas-prohibitive

**Confidence:** medium | **Locations:** `onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:147, onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:186, onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:312, onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:340, onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:751, onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:767, onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:770`

Both `lockToken()` and `lockNFT()` let anyone choose an arbitrary `_withdrawalAddress`, while withdrawals and lock transfers remove ids from `depositsByWithdrawalAddress[_withdrawalAddress]` via an unbounded linear scan. An attacker can therefore spam a victim with many tiny locks and inflate the victim's per-address array until removing later-positioned deposits becomes very expensive.

**Impact:** Affected users can face gas-heavy or even unexecutable withdrawals/transfers for some positions once their address list becomes large enough, creating a practical permissionless griefing/DoS vector against exits.

**Paths:**

- An attacker repeatedly creates tiny ERC20 or NFT locks with the victim set as `_withdrawalAddress`

- `depositsByWithdrawalAddress[victim]` grows without bound

- When the victim later withdraws or transfers a deposit whose id sits deep in that array, `_removeDepositsForWithdrawalAddress()` may consume too much gas and revert

*Round 1 | Agents: codex_1*

---

### F-004: The contract accepts arbitrary ERC721 transfers and permanently blackholes untracked NFTs

**Confidence:** high | **Locations:** `onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:135`

`onERC721Received()` always returns the acceptance selector regardless of context. Only `lockNFT()` records an incoming NFT in `lockedNFTs`, so any ERC721 sent directly to the locker via `safeTransferFrom` is accepted but never associated with a withdrawable deposit.

**Impact:** Mistakenly transferred or externally airdropped NFTs can become permanently stuck in the contract because no deposit record exists that would allow the normal withdrawal path to release them.

**Paths:**

- A user or third party calls `safeTransferFrom(..., LockToken, tokenId)` directly instead of `lockNFT()`

- The receiver hook accepts the NFT

- Because no `lockedNFTs` entry was created, there is no standard way to withdraw that NFT again

*Round 1 | Agents: codex_1*

---

### F-005: Referral fee math charges the discount percentage as the final fee

**Confidence:** high | **Locations:** `onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:522, onchain_auto/0x6dd27f2b82f78dd8a802a9228f340518280359f1/contracts/LockToken.sol:885`

`setReferralParams()` stores `referralDiscount` as a discount parameter, but `_chargeFeesReferral()` computes `feeInEth = feeInEth * referralDiscount / MAX_PERCENTAGE`. That makes a configured 5% discount (`500`) charge only 5% of the normal fee, instead of the intended 95%.

**Impact:** Whenever the referral path is enabled, users can underpay protocol fees by a large margin, materially bypassing the fee model and reducing protocol revenue.

**Paths:**

- Owner sets `referralDiscount` expecting it to mean a percentage discount off the full fee

- A user supplies any nonzero `referrer` to enter `_chargeFeesReferral()`

- The contract only collects `referralDiscount/MAX_PERCENTAGE` of the normal fee instead of applying that value as a discount

*Round 1 | Agents: codex_1*

---
