# Audit Report

**Total findings:** 4

## Critical (1)

### F-001: Batched ETH commitments can reuse one `msg.value` multiple times

**Confidence:** high | **Locations:** `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Utils/BoringBatchable.sol:35, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:263, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:274, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:279, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:510, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:512`

`BoringBatchable.batch()` uses `delegatecall`, so every subcall observes the original transaction `msg.value`. `commitEth()` derives the credited commitment from `msg.value` and never tracks whether that ETH was already consumed earlier in the same batch, allowing a single ETH payment to be counted repeatedly across multiple batched `commitEth()` calls.

**Impact:** An attacker can record far more commitment than they actually deposit. If the auction succeeds, they can buy a disproportionate share of auction tokens at other bidders' expense. If the auction fails, the recorded refund liabilities can exceed the contract's ETH balance, making the refund pool insolvent and allowing the attacker to drain ETH funded by honest participants.

**Paths:**

- Call `batch()` with multiple encoded `commitEth(attacker, true)` calls while sending ETH only once.

- Each delegatecalled `commitEth()` reuses the same `msg.value`, so `calculateCommitment(msg.value)` and `_addCommitment()` credit the attacker again.

- After settlement, claim inflated token allocation on success or withdraw an inflated ETH refund on failure.

*Round 1 | Agents: codex_1*

---

## High (1)

### F-002: Anyone can front-run initialization of an uninitialized auction and seize admin/proceeds control

**Confidence:** medium | **Locations:** `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Access/MISOAdminAccess.sol:31, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:138, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:176, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:179, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:448, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:629`

`initAuction()`/`initMarket()` are public, and the only one-time guard is the unrestricted `initAccessControls(_admin)`. The first caller therefore chooses the auction admin and payout wallet for any uninitialized instance. Initialization also immediately pulls auction tokens from the supplied `_funder`, so a victim who pre-approved the auction address can have their sale tokens swept into an attacker-controlled market.

**Impact:** A freshly deployed but uninitialized auction can be hijacked before the intended creator initializes it. The attacker can assign themselves admin, set their own payout wallet, and—if the seller has already approved the auction address—pull the seller's tokens into the contract and recover them via `cancelAuction()`. Even without an existing allowance, a front-runner can permanently brick the intended market by consuming the one-time initializer with arbitrary parameters.

**Paths:**

- Monitor for newly deployed/uninitialized auction instances.

- Call `initMarket()` or `initAuction()` first with attacker-controlled `_admin` and `_wallet`.

- If the intended funder has approved the auction address, initialization transfers the victim's auction tokens into the hijacked contract.

- Call `cancelAuction()` before any bids to send the auction tokens to the attacker-controlled wallet, or leave the auction permanently misconfigured/bricked.

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (2)

### F-003: The auction accounts for nominal transfer amounts instead of actual tokens received

**Confidence:** medium | **Locations:** `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:167, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:179, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:313, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:315, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:316, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:341, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:343`

The contract assumes token transfers are lossless. During initialization it sets `marketInfo.totalTokens = _totalTokens` before verifying how many auction tokens actually arrived, and during ERC20 bidding it credits `tokensToTransfer` to the bidder without measuring how many payment tokens were really received by the contract.

**Impact:** Fee-on-transfer, rebasing, or otherwise non-standard ERC20s can make the auction undercollateralized. If the auction token transfers less than `_totalTokens`, winners are promised more tokens than exist and later claimants can be shortchanged. If the payment token transfers less than the credited commitment, `commitmentsTotal` overstates collected funds, which can make finalization or failed-auction refunds revert or leave the seller underpaid.

**Paths:**

- Initialize an auction with a taxed/deflationary auction token so the contract receives fewer sale tokens than the recorded `totalTokens`.

- Or bid with a taxed payment token so `commitTokensFrom()` credits the full nominal amount while the contract receives less value.

- At settlement, token claims or payment forwarding/refunds become undercollateralized and some users or the seller are harmed.

*Round 1 | Agents: codex_1*

---

### F-004: Admin can redirect auction proceeds after users have already committed

**Confidence:** medium | **Locations:** `0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:113, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:463, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:476, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:606, 0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:610`

`setAuctionWallet()` lets the admin replace the payout wallet at any time and lacks the pre-start guard used by the time and price setters, even though the contract comments indicate wallet updates are intended only before the auction starts. Finalization always forwards the entire committed payment balance to the current `wallet` value.

**Impact:** A malicious or compromised admin can wait until users have already committed funds, switch the wallet to an attacker-controlled address, and then finalize the auction so all sale proceeds are redirected away from the intended seller.

**Paths:**

- Users commit ETH or payment tokens to the auction.

- Before finalization, the admin calls `setAuctionWallet(attackerControlledWallet)`.

- When `finalize()` runs, `_safeTokenPayment(paymentCurrency, wallet, commitmentsTotal)` sends the proceeds to the attacker-controlled wallet.

*Round 1 | Agents: opencode_1*

---
