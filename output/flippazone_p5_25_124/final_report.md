# Audit Report

**Total findings:** 5

## Critical (3)

### F-001: Anyone can drain auction ETH through unrestricted withdrawal functions

**Confidence:** high | **Locations:** `onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1342, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1348, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1354, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1359`

`ownerWithdraw`, `ownerWithdrawTo`, `ownerWithdrawAll`, and `ownerWithdrawAllTo` are all publicly callable and have no `onlyOwner` restriction. In particular, `ownerWithdrawAllTo` lets any caller forward the entire contract balance to an arbitrary address, while `ownerWithdrawTo` lets any caller redirect the winning proceeds after expiry.

**Impact:** Any external account can steal bidder deposits and sale proceeds, emptying the auction escrow before refunds or final settlement complete and leaving the contract insolvent.

**Paths:**

- Wait for the contract to accumulate ETH from bids or a buy-now purchase, then call `ownerWithdrawAllTo(attacker)` to transfer the full balance to the attacker.

- After the auction expires, call `ownerWithdrawTo(attacker)` to redirect the winning proceeds to the attacker instead of the owner.

*Round 1 | Agents: codex_1*

---

### F-002: Refund and bidder-withdraw paths are reentrant and can pay the same bid repeatedly

**Confidence:** high | **Locations:** `onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1326, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1331, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1332, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1364, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1368, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1370`

Both `refundBids` and `bidderWithdraw` send ETH with a low-level `call` before zeroing `bids[bidder]`. A malicious losing-bidder contract can reenter while its recorded balance is still non-zero and withdraw the same bid multiple times.

**Impact:** A single malicious bidder can drain ETH belonging to other bidders and even the seller proceeds, leaving the auction unable to honor legitimate withdrawals or refunds.

**Paths:**

- Bid from a contract, get outbid, then call `bidderWithdraw`; in the fallback, recursively call `bidderWithdraw` again before the outer call clears `bids[msg.sender]`.

- After the auction ends, trigger `refundBids`; when the attacker contract is paid, reenter `refundBids` or `bidderWithdraw` before its balance is zeroed to collect repeated refunds.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-003: `endAuction` can be reentered to mint multiple NFTs before the auction is marked finished

**Confidence:** high | **Locations:** `onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1310, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1314, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1318, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1323, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:795`

`endAuction` increments the token counter and calls `_safeMint` before setting `auctionEnded = true`. Because `_safeMint` invokes `onERC721Received` on contract recipients, a highest-bidder contract can reenter `endAuction` repeatedly while the auction still appears unfinished. There is no `MAX_SUPPLY` or `totalSupply` check to stop the extra mints.

**Impact:** An attacker can inflate a supposed 1/1 collection into multiple NFTs, permanently breaking scarcity and ownership assumptions for the asset being auctioned.

**Paths:**

- Become `highestBidder` using a contract that implements `onERC721Received`.

- After expiry, call `endAuction`; from `onERC721Received`, call `endAuction` again before the outer call sets `auctionEnded = true`, minting additional token IDs.

*Round 1 | Agents: codex_1*

---

## Medium (2)

### F-004: Batch refunds can silently erase a bidder's claim when ETH transfer fails

**Confidence:** high | **Locations:** `onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1329, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1331, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1332`

`refundBids` ignores the `success` flag from its low-level ETH transfer and zeroes `bids[bidder]` regardless. If the recipient rejects ETH or otherwise reverts, the payout fails but the bidder's recorded balance is still erased.

**Impact:** Losing bidders using non-payable or reverting smart-contract wallets can permanently lose their deposits when anyone triggers the batch refund path.

**Paths:**

- Bid from a contract whose receive/fallback function reverts on ETH transfers.

- After the auction ends, any user calls `refundBids`; the transfer fails, but the function still sets that bidder's balance to zero.

*Round 1 | Agents: codex_1*

---

### F-005: Hardcoded OpenSea proxy registry can auto-approve the wrong operator set on other deployments

**Confidence:** low | **Locations:** `onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1195, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1387, onchain_auto/0xe85a08cf316f695ebe7c13736c8cc38a7cc3e944/Contract.sol:1389`

The contract hardcodes `proxyRegistryAddress` to `0xa540...` and `isApprovedForAll` automatically trusts whatever proxy that external registry returns for each owner. If this code is deployed on a network where that address is not the intended OpenSea registry, users can inherit blanket approvals for an arbitrary contract-controlled operator.

**Impact:** On a misconfigured or non-mainnet deployment, arbitrary operators could receive transfer approval and steal users' NFTs without the users explicitly approving them.

**Paths:**

- Deploy the contract on a chain where `0xa5409ec958C83C3f309868babACA7c86DCB077c1` is controlled by an attacker or an unrelated contract.

- Return an attacker-controlled proxy from `proxies(owner)` and use the auto-approved operator path in `isApprovedForAll` to transfer the victim's NFT.

*Round 1 | Agents: codex_1*

---
