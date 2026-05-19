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
    "title": "CryptoPunks can be pledged with `nftType=1155`, permanently locking wrapped collateral and enabling bad debt",
    "locations": [
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:125",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:130",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:140",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:340"
    ],
    "claim": "When `_collection == punks`, the contract wraps the punk into `wrappedPunks` but keeps the user-supplied `_nftType` unchanged. A borrower can call `pledge`/`pledgeAndBorrow` with `_nftType = 1155`, causing the order to record an ERC721 wrapped punk as ERC1155. Any later withdrawal, redemption, liquidation settlement, or auction transfer uses the ERC1155 interface against `wrappedPunks` and reverts permanently.",
    "impact": "The collateral becomes irrecoverably stuck inside `XNFT`. If the borrower also borrowed against that order, the protocol can end up with uncollectible bad debt while the underlying punk remains frozen forever.",
    "paths": [
      "Call `pledgeAndBorrow(address(punks), punkId, 1155, xToken, borrowAmount)`",
      "`_depositPunk` mints the wrapped punk to `XNFT`, but the order stores `nftType = 1155`",
      "Any later `withdrawNFT`, `notifyRepayBorrow`, borrower redemption, or auction settlement reaches `transferNftInternal` and calls `IERC1155Upgradeable(wrappedPunks).safeTransferFrom(...)`",
      "The transfer reverts because `wrappedPunks` is ERC721, leaving the collateral stuck and the loan potentially unrecoverable"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "ETH payouts use `transfer`, letting contract bidders or liquidators permanently brick auctions and withdrawals",
    "locations": [
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:196",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:198",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:202",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:218",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:220",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:249",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:251",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:331",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:336"
    ],
    "claim": "For ETH-underlying pools, all refunds and profit distributions are pushed with Solidity's `transfer`, which hard-fails on recipients whose fallback needs more than 2300 gas or deliberately reverts. Because settlement always pays the previous bidder, liquidator, or pledger inline, any such participant can make future auction actions revert.",
    "impact": "A malicious contract can become liquidator or highest bidder and then block outbids, borrower redemption, or final settlement, freezing both the NFT and ETH proceeds. This can lock collateral indefinitely and prevent recovery of distressed loans.",
    "paths": [
      "A contract with a reverting/expensive `receive()` becomes the current `auctionAccount` in an ETH pool",
      "Any later outbid hits `doTransferOut(..., auctionAccount, auctionPrice)` and reverts",
      "Borrower redemption during protection similarly reverts when refunding the current `auctionAccount` or paying the liquidator",
      "After auction end, `withdrawNFT` can also revert forever while trying to compensate the pledger or liquidator in ETH"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "Liquidated collateral keeps routing airdrop value to the defaulted borrower until the auction fully ends",
    "locations": [
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:403",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:417",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:423",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:430"
    ],
    "claim": "During liquidation, `airDrop()` still sets `receiver = order.pledger` for the entire active auction window, even after default and even if third-party bidders have already escrowed funds. Anyone can call this public function and force the NFT through the airdrop execution path while the borrower receives the reward.",
    "impact": "The borrower can continue stripping economic value from collateral after default, reducing what liquidators and bidders are actually buying. Valuable airdrops can be siphoned away during liquidation, worsening lender recoveries and potentially creating insolvency if auctions price collateral assuming those rights are included.",
    "paths": [
      "An order is liquidated and a bidder posts an auction bid",
      "Before `auctionDuration` expires, anyone calls `airDrop(orderId, airDropContract, ercType)`",
      "Because the auction is still open, the function assigns the airdrop `receiver` to `order.pledger`",
      "The airdrop is claimed to the borrower while the eventual winner receives only the ex-airdrop NFT"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "Admin can sweep escrowed auction and redemption funds, not just protocol income",
    "locations": [
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:565",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:569"
    ],
    "claim": "The `withdraw()` admin function can transfer out any underlying balance held by `XNFT`, while `withdrawAuctionIncome()` is the only function that tracks protocol-owned income. This means the admin can drain bidder escrow, borrower redemption payments, or amounts reserved for later compensation/refunds.",
    "impact": "Escrowed user funds can be stolen outright. Even if not stolen permanently, removing these balances breaks future settlement flows, causing auctions, redemptions, or withdrawals to revert because the contract no longer holds the funds it promised to pay out.",
    "paths": [
      "Users bid in an auction or a borrower pays redemption funds into `XNFT`",
      "Admin calls `withdraw(xToken, amount)` and drains the underlying asset from the contract",
      "A later outbid, borrower redemption, or `withdrawNFT` tries to refund/compensate participants from an empty balance and fails"
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "high",
    "title": "Admin `claim()` is an unrestricted arbitrary call that can transfer pledged NFTs out of escrow",
    "locations": [
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:588",
      "0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:589"
    ],
    "claim": "`claim(address airdop, bytes memory byteCode)` performs an arbitrary external call from the `XNFT` contract with no restriction that the target or calldata actually relate to an airdrop. Since `XNFT` owns pledged NFTs, the admin can call collateral token contracts directly and execute transfer functions as the owner.",
    "impact": "The admin can bypass all loan and liquidation accounting and steal escrowed NFTs at will. Collateral can disappear while orders remain active, leaving lenders undercollateralized and borrowers unable to recover their assets.",
    "paths": [
      "A pledged NFT is held by `XNFT`",
      "Admin calls `claim(order.collection, transferCalldata)` where `transferCalldata` invokes the NFT contract's transfer function from `address(this)` to an arbitrary recipient",
      "Because the call originates from `XNFT`, the token contract treats it as the owner and transfers the collateral out of escrow"
    ]
  }
]

```

### Agent: opencode_1
```
Let me read the main contract and key interface files to analyze for vulnerabilities.
Let me also read the remaining interface files:
Based on my analysis of the XNFT.sol contract and related interfaces, here are the security vulnerabilities I found:

[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "airDrop function allows NFT theft via malicious xAirDrop contract",
    "locations": ["0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:403-434"],
    "claim": "The airDrop function transfers the NFT to xAirDrop contract, calls execution(), then expects NFT back. If xAirDrop is malicious or compromised, it can permanently steal all NFTs held by the contract.",
    "impact": "Any NFT held by the contract can be stolen through the airdrop mechanism. All pledged NFTs are at risk.",
    "paths": ["1. Admin calls setXAirDrop() with malicious contract address", "2. Attacker calls airDrop() or batchAirDrop() with any orderId", "3. NFT is transferred to malicious xAirDrop which keeps it"]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "setXAirDrop allows admin to set malicious contract to steal all NFTs",
    "locations": ["0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:584-586"],
    "claim": "The setXAirDrop function allows admin to change xAirDrop address at any time to a malicious contract, enabling theft of all NFTs held by the contract.",
    "impact": "Admin can steal all NFTs stored in the contract at any time.",
    "paths": ["1. Admin calls setXAirDrop(maliciousAddress)", "2. Admin calls airDrop() to transfer NFTs to malicious contract"]
  },
  {
    "id": "F-003",
    "severity": "Critical",
    "confidence": "high",
    "title": "claim function allows arbitrary code execution enabling fund theft",
    "locations": ["0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:588-591"],
    "claim": "The claim function uses low-level call to execute arbitrary bytecode on any contract. Admin can use this to drain all funds and tokens from the contract.",
    "impact": "All protocol funds (ETH and ERC20 tokens) can be stolen by admin.",
    "paths": ["1. Admin calls claim(targetAddress, maliciousData)", "2. Arbitrary code executes, transferring all funds to admin"]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "Missing nonReentrant modifier in notifyOrderLiquidated allows reentrancy attack",
    "locations": ["0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:274-294"],
    "claim": "notifyOrderLiquidated performs NFT transfer (transferNftInternal) without nonReentrant modifier. This allows reentrancy exploitation where a malicious contract can reenter during the NFT transfer.",
    "impact": "Attacker can potentially steal NFTs during liquidation by reentering the function.",
    "paths": ["1. Attacker creates malicious contract with onERC721Received", "2. Attacker liquidates their own order", "3. During NFT transfer, malicious contract's callback reenters and manipulates state"]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "high",
    "title": "Missing nonReentrant modifier in notifyRepayBorrow allows reentrancy attack",
    "locations": ["0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:296-306"],
    "claim": "notifyRepayBorrow performs NFT transfer without nonReentrant modifier, enabling reentrancy exploitation.",
    "impact": "Attacker can potentially manipulate state or steal NFTs through reentrancy.",
    "paths": ["1. Attacker calls notifyRepayBorrow", "2. During NFT transfer, malicious callback reenters the function"]
  },
  {
    "id": "F-006",
    "severity": "High",
    "confidence": "high",
    "title": "setPunks allows admin to set malicious punk contracts to steal user NFTs",
    "locations": ["0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:593-598"],
    "claim": "Admin can change punks and wrappedPunks addresses to malicious contracts. Combined with _depositPunk function, admin can steal user CryptoPunks.",
    "impact": "Admin can steal users' CryptoPunks during deposit or steal already wrapped punks.",
    "paths": ["1. Admin calls setPunks(maliciousPunks, maliciousWrappedPunks)", "2. When user calls pledge() with punk collection, NFT goes to malicious contract"]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "medium",
    "title": "No minimum price protection in auction allows unfair liquidation",
    "locations": ["0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:172-228"],
    "claim": "The auction function accepts any amount as long as it meets the minimum markup percentage, but does not have a floor price based on actual collateral value. Liquidator can purchase NFTs at significant discount.",
    "impact": "Borrowers may lose significant value in liquidation even when the market recovers.",
    "paths": ["1. NFT has high market value but borrows small amount", "2. Liquidator purchases at minimum markup (e.g., 5% above last price)", "3. Borrower loses significant equity"]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "medium",
    "title": "No slippage protection in doTransferIn for ERC20 tokens",
    "locations": ["0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:313-329"],
    "claim": "The doTransferIn function uses balanceBefore/After check but doesn't account for transfer fees or deflationary tokens that could cause amount mismatch.",
    "impact": "Protocol may not receive expected token amounts with fee-on-transfer tokens.",
    "paths": ["1. Using fee-on-transfer token as collateral", "2. TransferIn checks pass but actual amount received is less", "3. Protocol accounting becomes incorrect"]
  },
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "medium",
    "title": "No access control on batchAirDrop allows anyone to trigger airdrops",
    "locations": ["0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:436-440"],
    "claim": "batchAirDrop has no access control, allowing anyone to trigger airdrops on any order. Combined with F-001/F-002, this amplifies the attack surface.",
    "impact": "Any user can trigger airdrops, potentially enabling mass NFT theft if xAirDrop is malicious.",
    "paths": ["1. If xAirDrop is malicious, anyone can trigger batchAirDrop to drain all NFTs"]
  },
  {
    "id": "F-010",
    "severity": "Medium",
    "confidence": "low",
    "title": "Division before multiplication can cause precision loss in auctionAllowed",
    "locations": ["0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:167"],
    "claim": "Expression 'lastPrice.mul(_increasingMin).div(1e18)' performs multiplication before division, which can cause precision loss for small values.",
    "impact": "Minimum auction increment may be underestimated in some cases.",
    "paths": ["1. Small _increasingMin values result in rounding down to 0"]
  },
  {
    "id": "F-011",
    "severity": "Low",
    "confidence": "medium",
    "title": "Fixed gas limit in ETH transfer may cause transfer failures",
    "locations": ["0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:325"],
    "claim": "ETH transfer uses fixed transferEthGasCost which may be insufficient if recipient is a contract that requires more gas.",
    "impact": "ETH refunds may fail silently, causing users to lose excess ETH sent.",
    "paths": ["1. User sends excess ETH in transaction", "2. Recipient contract requires more than transferEthGasCost", "3. Transfer fails, user loses excess ETH"]
  },
  {
    "id": "F-012",
    "severity": "Low",
    "confidence": "medium",
    "title": "No validation that collection whitelist settings are reasonable",
    "locations": ["0x39360ac1239a0b98cb8076d4135d0f72b7fd9909/contracts/XNFT.sol:500-516"],
    "claim": "setCollectionlWhitListInternal doesn't validate that auctionDuration, redeemProtection, and increasingMin are within reasonable bounds.",
    "impact": "Admin can set unreasonable values that break protocol economics.",
    "paths": ["1. Admin sets extremely small auction duration", "2. Users cannot properly participate in liquidation"]
  }
]

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
