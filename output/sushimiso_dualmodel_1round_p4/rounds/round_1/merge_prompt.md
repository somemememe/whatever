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
    "title": "Batched ETH bids can reuse a single `msg.value` to mint multiple commitments",
    "locations": [
      "0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Utils/BoringBatchable.sol:35",
      "0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:263",
      "0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:274",
      "0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:279"
    ],
    "claim": "`batch()` uses `delegatecall`, so every subcall sees the same original `msg.value`. Because `commitEth()` computes the credited bid from `msg.value` and never tracks whether that value was already consumed inside the batch, one ETH transfer can be counted repeatedly across multiple batched `commitEth()` calls.",
    "impact": "An attacker can obtain a much larger recorded commitment than the ether actually deposited. In a successful auction this buys auction tokens at a steep discount; in a failed ETH auction it can make the refund pool insolvent and let the attacker withdraw more ETH than they paid, stealing from honest participants.",
    "paths": [
      "Call `batch()` with multiple encoded `commitEth(attacker, true)` calls and send ETH only once.",
      "Each delegatecalled `commitEth()` reuses the same `msg.value`, so `commitments[attacker]` and `commitmentsTotal` increase multiple times.",
      "After the auction ends, withdraw inflated token/refund entitlement via `withdrawTokens()`."
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "medium",
    "title": "Any first caller can initialize an uninitialized auction and seize admin and wallet control",
    "locations": [
      "0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Access/MISOAdminAccess.sol:31",
      "0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:138",
      "0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:176",
      "0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:179",
      "0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:448",
      "0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:629"
    ],
    "claim": "`initAuction()` and `initMarket()` are public and their only one-time guard is the unrestricted `initAccessControls()` call. The first caller chooses the admin and wallet, and initialization immediately pulls auction tokens from the supplied `_funder` into the auction contract.",
    "impact": "Any freshly deployed or otherwise uninitialized auction instance can be hijacked. If the intended funder has already approved the auction address, an attacker can initialize the market with their own admin/wallet, pull the seller's tokens into the contract, and then recover them through `cancelAuction()`. Even without a funded allowance, the attacker can permanently brick the intended market by consuming the one-time initializer.",
    "paths": [
      "Observe an uninitialized auction instance.",
      "Call `initMarket()`/`initAuction()` first with attacker-controlled `_admin` and `_wallet`.",
      "If `_funder` has approved the auction, initialization transfers sale tokens into the hijacked contract.",
      "Call `cancelAuction()` as the new admin to send the auction tokens to the attacker-controlled wallet."
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "medium",
    "title": "The auction books nominal token amounts instead of actual received amounts",
    "locations": [
      "0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:167",
      "0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:179",
      "0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:313",
      "0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:315",
      "0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:316"
    ],
    "claim": "Both auction funding and ERC20 bidding assume the transfer amount equals the amount received. The contract sets `totalTokens = _totalTokens` before checking the actual token balance change, and it credits `tokensToTransfer` to a bidder's commitment without measuring how many payment tokens actually arrived.",
    "impact": "Fee-on-transfer, rebasing, or otherwise non-standard ERC20s can leave the auction undercollateralized. A taxed auction token means winners cannot receive the advertised token supply; a taxed payment token means bidders are credited for more than the seller actually receives. In both cases settlement can become unfair or insolvent.",
    "paths": [
      "Initialize the auction with an auction token that transfers less than `_totalTokens` to the contract, then sell the larger recorded `totalTokens` anyway.",
      "Or use a transfer-tax payment token so `commitTokensFrom()` credits the full `_amount` while the contract receives less value than recorded."
    ]
  }
]

```

### Agent: opencode_1
```
[{"id":"F-001","severity":"Critical","confidence":"high","title":"Missing Access Control on initAuction allows complete token theft","locations":["0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:138-180"],"claim":"The initAuction function has no access control and can be called by anyone. An attacker can initialize an already-funded auction with themselves as admin, then call finalize() to steal all auction tokens.","impact":"If tokens have been deposited into the contract for an auction, any attacker can initialize the auction with themselves as admin and steal all tokens by calling finalize(). The attacker only needs to know the token address and that tokens are present in the contract.","paths":["1. Attacker observes auction token has been transferred to DutchAuction contract (via ERC20 balanceOf)","2. Attacker calls initAuction() with their address as _admin","3. Attacker calls finalize() to transfer all auction tokens to their controlled wallet"]},{"id":"F-002","severity":"High","confidence":"high","title":"Arbitrary wallet change after auction commitments","locations":["0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:606-613"],"claim":"setAuctionWallet function has no check to ensure auction has not started (commitmentsTotal == 0), allowing admin to change the payment destination wallet after participants have already committed funds.","impact":"Admin can change the wallet address to their own address after participants have committed ETH/tokens, stealing all auction proceeds.","paths":["1. Participants commit funds to auction","2. Admin calls setAuctionWallet(attackerControlledAddress)","3. Admin calls finalize() to send all funds to attacker-controlled address"]},{"id":"F-003","severity":"High","confidence":"high","title":"Inconsistent use of nonReentrant modifier","locations":["0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:263-285","0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:521-537","0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:545-560","0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:606-613"],"claim":"commitEth, setDocument, setDocuments, removeDocument, setList, and setAuctionWallet lack nonReentrant modifier while commitTokensFrom, withdrawTokens, cancelAuction, and finalize have it.","impact":"Functions without reentrancy protection are vulnerable to reentrant calls that could manipulate state variables or cause unexpected behavior.","paths":["1. Attacker calls commitEth in a reentrant manner","2. Attacker calls setAuctionWallet within the same transaction"]},{"id":"F-004","severity":"High","confidence":"medium","title":"Division by zero in price calculation functions","locations":["0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:204-207","0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:364-370","0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:355-357"],"claim":"tokenPrice(), calculateCommitment(), and totalTokensCommitted() can revert due to division by zero if clearingPrice() returns 0 (when minimumPrice is 0).","impact":"Auction becomes unusable if clearing price is calculated as 0, causing all calls to these view functions to revert and breaking integration with off-chain tools.","paths":["1. Admin initializes auction with minimumPrice = 0 (or minimum price calculated results in 0)","2. Any user calling tokenPrice(), calculateCommitment(), or totalTokensCommitted() gets division by zero error"]},{"id":"F-005","severity":"Medium","confidence":"high","title":"Deprecated Solidity version 0.6.12","locations":["0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:1"],"claim":"Contract uses Solidity 0.6.12 which is an older version with known issues and has reached end-of-life.","impact":"Using deprecated compiler versions may introduce security vulnerabilities that have been fixed in newer versions. Code may be incompatible with modern tooling.","paths":[]},{"id":"F-006","severity":"Medium","confidence":"medium","title":"Outdated .transfer() pattern for ETH transfers","locations":["0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Utils/SafeTransfer.sol:28"],"claim":"_tokenPayment uses .transfer() which only provides 2300 gas (EIP-1884), while _safeTokenPayment uses .call() which is the recommended pattern.","impact":"ETH transfers via _tokenPayment may fail for contracts that require more than 2300 gas, causing the transaction to revert.","paths":[]},{"id":"F-007","severity":"Medium","confidence":"low","title":"Comment and code discrepancy for finalizeTimeExpired","locations":["0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:404-408"],"claim":"The comment states '14 days' but the code uses '7 days' (block.timestamp + 7 days).","impact":"Confusing for integrators who rely on documentation. May lead to incorrect assumptions about auction finalization timing.","paths":[]},{"id":"F-008","severity":"Low","confidence":"high","title":"Wallet address can trigger finalization","locations":["0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:463-469"],"claim":"The wallet address (payment recipient) is allowed to call finalize(), creating a conflict of interest.","impact":"Wallet owner can finalize the auction themselves, potentially before the intended timeout, to gain early access to funds.","paths":[]},{"id":"F-009","severity":"Low","confidence":"medium","title":"IERC20 interface requires permit which many tokens lack","locations":["0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/interfaces/IERC20.sol:15-23","0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Utils/BoringBatchable.sol:52-63"],"claim":"The IERC20 interface includes permit() function (EIP-2612) which many tokens do not implement, and BoringBatchable.permitToken() calls this on any token.","impact":"Contracts using BoringBatchable.permitToken() will revert when used with tokens that don't support permit(), causing transaction failures.","paths":[]},{"id":"F-010","severity":"Low","confidence":"medium","title":"Missing validation for pointList contract","locations":["0x4c4564a1fe775d97297f9e3dc2e762e0ed5dda0e/contracts/Auctions/DutchAuction.sol:555-560"],"claim":"_setList does not verify that the pointList contract implements the IPointList interface.","impact":"If a non-conforming contract is set as pointList, calls to IPointList(pointList).hasPoints() will revert, breaking auction participation.","paths":["1. Admin sets a non-IPointList contract as pointList","2. Users cannot commit to auction due to revert in hasPoints call"]}]

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
