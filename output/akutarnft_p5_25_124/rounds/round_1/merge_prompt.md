Below are findings and vulnerability signals from 2 agents auditing the same codebase,
plus accumulated findings from previous rounds. You need to inspect the source code when needed.

You are the merge and review layer for a audit.

Your task:
- merge new or materially improved reportable issues into the accumulated findings
- reconstruct plausible but poorly written findings or signals into low-confidence findings when the code supports them
- reject clearly non-reportable candidates with your reasons
- try to use this round's signals and the source code to look for additional findings yourself

Prefer downgrading severity or confidence over discarding a plausible issue.
Keep findings that can cause realistic protocol-level harm, including fund loss,
theft, insolvency, permanent lockup, economic manipulation, or permissionless DoS and some other realistic issues.

## Accumulated Findings
None yet.

## This Round's Agent Outputs
### Agent: codex_1
```
[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Project funds can be permanently locked by comparing bidder progress to NFT count",
    "locations": [
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:462",
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:463",
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:466",
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:608",
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:616"
    ],
    "claim": "`refundProgress` advances once per bidder record, while `totalBids` counts NFTs. If any bidder purchases more than one NFT, the maximum reachable `refundProgress` is lower than `totalBids`, so `claimProjectFunds()` can remain permanently unreachable.",
    "impact": "All ETH left in the auction after refunds becomes permanently stuck in the contract, locking the project's proceeds with no recovery path.",
    "paths": [
      "A bidder calls `bid(2)` or `bid(3)`",
      "`totalBids` increases by 2 or 3, but `bidIndex` and later `refundProgress` increase by only 1",
      "`processRefunds()` eventually finishes all bidder records, yet `refundProgress < totalBids` still holds",
      "`claimProjectFunds()` always reverts with `Refunds not yet processed`"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Any bidder can brick refund processing by reverting on ETH receipt",
    "locations": [
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:591",
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:599",
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:601",
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:602"
    ],
    "claim": "`processRefunds()` pushes ETH with a low-level call and reverts the entire batch if the current bidder rejects payment. A malicious bidder contract can therefore halt `refundProgress` at its own index forever.",
    "impact": "Refund processing for all subsequent bidders can be permanently DoSed, and project fund withdrawal is also blocked because the contract never advances past the malicious entry.",
    "paths": [
      "Attacker bids through a contract whose `receive()` or fallback always reverts",
      "After the auction, `processRefunds()` reaches the attacker's entry",
      "The refund transfer reverts, so the whole transaction reverts and `refundProgress` does not advance",
      "Every future `processRefunds()` attempt fails at the same bidder"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "Emergency withdrawal can give bidders a full refund even after they already received NFTs",
    "locations": [
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:569",
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:572",
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:576",
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:577"
    ],
    "claim": "`emergencyWithdraw()` only checks a 3-day timeout and `finalProcess == 0`; it never verifies whether the caller's NFTs were already airdropped. A bidder can therefore recover their entire bid while keeping any NFTs already delivered to them if the overall airdrop is delayed.",
    "impact": "Bidders can obtain free NFTs and drain the escrowed sale proceeds, potentially leaving the auction insolvent and preventing honest users from receiving their expected settlement.",
    "paths": [
      "Auction ends and NFT distribution starts",
      "Some bidder receives NFT(s), but the overall airdrop is still incomplete after 3 days",
      "That bidder calls `emergencyWithdraw()`",
      "The contract sends back `bidData.price * bidData.bidsPlaced` without checking whether the bidder already received NFT(s)"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "Zero-amount bids let sybils create dummy bidder records and unlock premature project withdrawal",
    "locations": [
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:493",
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:505",
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:535",
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:539",
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:608",
      "onchain_auto/0xf42c318dbfbaab0eee040279c6a2588fa01a961d/Contract.sol:616"
    ],
    "claim": "Because `bid(0)` is allowed, new addresses can create bidder entries without increasing `totalBids`. `processRefunds()` advances over these dummy entries, but `claimProjectFunds()` only checks `refundProgress >= totalBids`, so the owner can withdraw funds before later real bidders are processed.",
    "impact": "Refunds reserved for honest bidders can be drained to the project address before their records are reached, causing underpayment or complete non-payment of later refunds and emergency withdrawals.",
    "paths": [
      "Attacker uses many sybil addresses to call `bid(0)` during the auction",
      "Each call creates a new `allBids` entry and increments `bidIndex`, but leaves `totalBids` unchanged",
      "`processRefunds()` advances `refundProgress` across the dummy entries until it is already `>= totalBids`",
      "Owner calls `claimProjectFunds()` and withdraws the full balance while real bidder records later in the index remain unprocessed"
    ]
  }
]

```

### Agent: opencode_1
```
[{"id":"F-001","severity":"Critical","confidence":"high","title":"Reentrancy vulnerability in _bid() function","locations":["Contract.sol:545-549"],"claim":"The _bid() function sends refund to the bidder via an external call (line 547) before completing all state updates (lines 542-543). This violates the checks-effects-interactions pattern.","impact":"An attacker can recursively call bid() through a malicious contract's receive function to drain contract funds or manipulate auction state before state updates occur.","paths":["1. Attacker deploys a malicious contract with a receive() that calls AkuAuction.bid()\n2. Attacker calls bid() on the auction contract\n3. The refund (line 547) triggers the malicious contract's receive()\n4. The malicious contract calls bid() again, exploiting the not-yet-updated state"]},{"id":"F-002","severity":"Critical","confidence":"high","title":"Reentrancy vulnerability in processRefunds() function","locations":["Contract.sol:599-603"],"claim":"The processRefunds() function makes an external call to refund bidders (line 601) after setting finalProcess (line 599) but before completing the loop iteration, allowing reentrancy.","impact":"An attacker can recursively call processRefunds() to drain contract funds.","paths":["1. Attacker places a bid\n2. processRefunds() processes their bid and sends refund\n3. Attacker contract's receive() calls processRefunds() again\n4. Since state update happens after external call, attacker can get multiple refunds"]},{"id":"F-003","severity":"Critical","confidence":"high","title":"Reentrancy vulnerability in emergencyWithdraw() function","locations":["Contract.sol:576-578"],"claim":"The emergencyWithdraw() function sends ETH to the bidder (line 577) before updating finalProcess state (line 576).","impact":"An attacker can recursively call emergencyWithdraw() to drain contract funds.","paths":["1. Attacker calls emergencyWithdraw()\n2. The external call triggers their receive() fallback\n3. receive() calls emergencyWithdraw() again\n4. finalProcess is checked (line 574) but updated after the call (line 576), allowing multiple withdrawals"]},{"id":"F-004","severity":"High","confidence":"high","title":"Integer underflow in processRefunds() refund calculation","locations":["Contract.sol:594"],"claim":"The calculation (bidData.price - price) can underflow if the current auction price is higher than the original bid price. Since both are uint256, underflow will cause the transaction to revert.","impact":"If the auction price increases (e.g., due to time passing or price mechanism changes), processRefunds() will revert for all bidders, permanently locking the refund process.","paths":["1. Bidder places bid at lower price\n2. Later, current price increases (e.g., auction continues with higher price)\n3. When processRefunds() is called, it tries to calculate (lower price - higher price)\n4. Underflow causes revert, refunds are blocked"]},{"id":"F-005","severity":"High","confidence":"high","title":"Logic error in claimProjectFunds() prevents fund withdrawal","locations":["Contract.sol:616"],"claim":"The condition require(refundProgress >= totalBids, ...) is logically flawed - refundProgress is an index pointer (max ~5000 bidders) while totalBids is total NFT count (up to 5495). These are incomparable values.","impact":"The owner can never withdraw project funds because refundProgress (which ends at ~bidIndex-1, where bidIndex is number of unique bidders) will never be >= totalBids (which counts total NFTs bid). This permanently locks project funds.","paths":["1. Auction ends, all bids placed (e.g., 5000 NFTs to 1000 bidders)\n2. Refunds are fully processed (refundProgress = 1000)\n3. Airdrop completes\n4. Owner calls claimProjectFunds()\n5. Reverts because 1000 >= 5000 is false"]},{"id":"F-006","severity":"High","confidence":"medium","title":"Owner can bypass airdrop completion check","locations":["Contract.sol:565-567","Contract.sol:617"],"claim":"The owner can set any address as the NFT contract via setNFTContract(). A malicious or compromised owner can set a contract that returns a manipulated airdropProgress() value.","impact":"The owner can claim project funds even when the airdrop is not complete, potentially stealing user funds or leaving bidders without their NFTs.","paths":["1. Owner calls setNFTContract() with address of a malicious contract\n2. Malicious contract's airdropProgress() returns any value >= totalBids\n3. Owner calls claimProjectFunds()\n4. Check passes despite airdrop being incomplete\n5. Project receives funds but airdrop may never complete"]},{"id":"F-007","severity":"Low","confidence":"high","title":"No deadline extension for last-minute bidders","locations":["Contract.sol:527-529"],"claim":"When auction reaches totalForAuction, expiresAt is set to block.timestamp, immediately ending the auction without any grace period.","impact":"Bidders who submit bids in the same block that fills the auction may not have time to confirm their transaction, potentially losing their bid opportunity.","paths":["1. Auction has 1 NFT remaining\n2. Two bidders submit bids in the same block\n3. First bid fills auction, expiresAt set to current timestamp\n4. Second bid reverts because auction already expired"]},{"id":"F-008","severity":"Low","confidence":"medium","title":"Potential griefing via front-running bids","locations":["Contract.sol:501-550"],"claim":"The auction has no minimum bid increment. While getPrice() returns the current price, large players can front-run smaller bids by bidding simultaneously.","impact":"A large bidder can monitor the mempool and outbid smaller bidders by bidding at the same price point, making it difficult for small bidders to win.","paths":["1. Small bidder submits bid(amount=1)\n2. Large bidder sees this in mempool, submits bid with same amount\n3. Both bids processed, but both pay same price\n4. Small bidder may be outcompeted on quantity"]}]

```



## Output
Return a JSON object with:
- `findings`: the COMPLETE updated findings list
- `rejected_candidates`: candidates rejected from this round, with concise reasons

Each `findings` element must have:
- `id`
- `severity`
- `confidence`
- `title`
- `locations`
- `claim`
- `impact`
- `paths`
- `round`
- `source_agents`

Preserve existing IDs for surviving findings whenever possible.
`source_agents` must include every agent that materially supports the final finding.

Each `rejected_candidates` element must have:
- `title`
- `source_agents`
- `reason`

Output ONLY valid JSON. No markdown. No prose.
