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
    "title": "Redeem accepts arbitrary contracts and can drain any ERC20 balance held by the teller",
    "locations": [
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:137",
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:138",
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:140",
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:141"
    ],
    "claim": "`redeem()` trusts the caller-supplied `token_` address without verifying that it is a bond token deployed by this teller. An attacker can pass a malicious contract that returns a past `expiry()`, makes `burn()` a no-op, and points `underlying()` at any ERC20 currently held by the teller.",
    "impact": "Any token balance sitting in the teller can be stolen permissionlessly, including payout reserves backing live bonds, tokens deposited via `create()`, and accumulated fee balances.",
    "paths": [
      "Deploy a fake contract exposing `expiry()`, `burn(address,uint256)`, and `underlying()` with the same ABI as `ERC20BondToken`.",
      "Make `expiry()` return a matured timestamp and `burn()` do nothing.",
      "Make `underlying()` return the address of a valuable ERC20 held by the teller.",
      "Call `redeem(fakeToken, amount)` to receive `amount` of that ERC20 from the teller without owning any legitimate bond tokens."
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Purchases into undeployed fixed-expiry markets can succeed while minting no bond tokens",
    "locations": [
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/bases/BondBaseTeller.sol:157",
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:83",
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:86",
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:104"
    ],
    "claim": "The purchase path never checks that `bondTokens[underlying][expiry]` exists before calling `.mint()`. If nobody has called `deploy()` for that `(underlying, expiry)` pair yet, `_handlePayout()` calls `mint()` on `address(0)` instead of reverting, so the transaction can complete after collecting quote tokens and funding payout reserves while issuing no claim token to the buyer.",
    "impact": "Buyers can lose the full value of a bond purchase and receive no redeemable position. The payout tokens remain stranded in the teller with no on-chain record tying them to the buyer.",
    "paths": [
      "A future-dated market is live, but no one has called `deploy(payoutToken, vesting)` yet.",
      "A user calls `purchase(...)` on that market.",
      "`_handleTransfers()` pulls quote tokens from the user and sources payout tokens into the teller.",
      "`_handlePayout()` executes `bondTokens[underlying][expiry].mint(...)` against the zero address, so no bond tokens are minted.",
      "The transaction returns success, but the user has paid in and has no redeemable asset."
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "Redeem burns first and ignores ERC20 transfer failures, enabling permanent loss on false-return tokens",
    "locations": [
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:137",
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:140",
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/BondFixedExpiryTeller.sol:141"
    ],
    "claim": "`redeem()` burns the user's bond tokens and then performs a raw `underlying().transfer(...)` while ignoring the returned boolean. For tokens that return `false` instead of reverting on failed transfers, the transaction can succeed after the burn without delivering any payout.",
    "impact": "Bond holders can suffer irreversible loss of their full redeemed amount. A malicious market creator can deliberately choose a payout token that behaves this way and sell bonds that become worthless at redemption time.",
    "paths": [
      "A market uses a payout token whose `transfer` returns `false` under teller-to-user transfers.",
      "A user acquires legitimate bond tokens for that market.",
      "On `redeem()`, the teller burns the user's bond balance first.",
      "The underlying token's `transfer` returns `false`, but the teller does not check it and does not revert.",
      "The user ends the transaction with fewer bond tokens and no underlying payout."
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "low",
    "title": "Purchase prices against one market snapshot but settles against a second snapshot",
    "locations": [
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/bases/BondBaseTeller.sol:139",
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/bases/BondBaseTeller.sol:141",
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/bases/BondBaseTeller.sol:147",
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/bases/BondBaseTeller.sol:173",
      "onchain_auto/0x007fe7c498a2cf30971ad8f2cbc36bd14ac51156/src/bases/BondBaseTeller.sol:175"
    ],
    "claim": "`purchase()` reads market configuration once to price the bond and call `purchaseBond()`, then `_handleTransfers()` re-reads market configuration and uses the second result to decide who receives quote tokens and which payout token must be delivered. If a registered auctioneer mutates owner/callback/token fields during `purchaseBond()`, the teller can settle against different parameters than the ones the buyer was quoted.",
    "impact": "A buggy or malicious auctioneer implementation can redirect user quote tokens to an attacker-controlled owner/callback or swap the expected payout token during settlement, breaking buyer assumptions and potentially causing theft or issuance of misbacked bonds.",
    "paths": [
      "A registered auctioneer returns benign market info in the first `getMarketInfoForPurchase(id_)` call.",
      "Inside `purchaseBond()`, it mutates the market's owner, callback, payout token, or quote token.",
      "The teller then calls `_handleTransfers()`, which fetches the changed market info and settles using the new values instead of the quoted ones."
    ]
  }
]

```

### Agent: opencode_1
```
I'll audit the smart contracts in the specified directory. Let me first explore the structure and then read all the relevant files.
Let me read all the contract files:
Now let me read the main contracts:
Now let me read the interface and library files:
Now let me read the library files:
Now I'll analyze the contracts for vulnerabilities and prepare the JSON output.

Based on my analysis, I found several security vulnerabilities:

**F-001: No Access Control on setProtocolFee**
- The `setProtocolFee` function has `requiresAuth` but protocolFee is initialized to 0, and there is no minimum enforcement. This allows setting arbitrary high fees.

**F-002: No Access Control on claimFees**
- The `claimFees` function has no access control check - anyone can claim any user's accumulated fees.

**F-003: Fee-on-transfer Token Vulnerability**
- The balance check in `BondFixedExpiryTeller.create` (line 112) and `_handleTransfers` (lines 184-186, 205-208) uses `balanceAfter >= balanceBefore + amount` which will revert for fee-on-transfer tokens even though the comment claims they are "not supported".

**F-004: No Minimum Protocol Fee**
- `protocolFee` is initialized to 0 with no minimum enforced. The comment says "must be greater than 30 bps" but there's no validation.

**F-005: Arbitrary Referrer Fee Setting**
- In `setReferrerFee`, any fee up to 5e4 (50%) can be set without any validation that it's reasonable.

**F-006: Unchecked Callback Result**
- The callback in `_handleTransfers` doesn't verify the callback returned the correct amount - it only checks balance increase.

**F-007: ERC20BondToken Mint/Burn Access Control**
- Only checks `msg.sender != teller()` - if teller is address(0), anyone can mint/burn.

**F-008: Missing Initialization of guardian_**
- The Auth constructor receives `guardian_` but the contract doesn't use it - no way to recover if owner is locked out.

Let me verify a few more details:
Based on my thorough analysis, here are the security vulnerabilities I found:

[
  {
    "id": "F-001",
    "severity": "High",
    "confidence": "high",
    "title": "Unprotected claimFees allows stealing accumulated fees",
    "locations": [
      "bases/BondBaseTeller.sol:99"
    ],
    "claim": "The claimFees function has no access control modifier, allowing anyone to claim fees accumulated for any address by specifying that address as msg.sender",
    "impact": "An attacker can claim all accumulated protocol and referrer fees by calling claimFees with their own address as msg.sender, stealing all rewards stored in the rewards mapping",
    "paths": [
      "Call claimFees(tokens, attackerAddress) where attacker passes themselves as the fee recipient"
    ]
  },
  {
    "id": "F-002",
    "severity": "Medium",
    "confidence": "high",
    "title": "No minimum protocol fee enforcement",
    "locations": [
      "bases/BondBaseTeller.sol:84",
      "bases/BondBaseTeller.sol:94"
    ],
    "claim": "The protocolFee is initialized to 0 and setProtocolFee has no minimum value check despite documentation stating 'must be greater than 30 bps'",
    "impact": "Protocol can set zero fees, allowing bond purchases without any protocol revenue, or can be accidentally set to an ineffective low value",
    "paths": [
      "Call setProtocolFee(0) to set zero protocol fee"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Fee-on-transfer token handling breaks for legitimate tokens",
    "locations": [
      "BondFixedExpiryTeller.sol:110",
      "BondFixedExpiryTeller.sol:112",
      "bases/BondBaseTeller.sol:183",
      "bases/BondBaseTeller.sol:184",
      "bases/BondBaseTeller.sol:185",
      "bases/BondBaseTeller.sol:205",
      "bases/BondBaseTeller.sol:206",
      "bases/BondBaseTeller.sol:207"
    ],
    "claim": "Balance checks use pattern 'balanceAfter < balanceBefore + amount' which fails for tokens with legitimate transfer fees (e.g., USDT, USDC) where the received amount is less than the sent amount",
    "impact": "The protocol will reject legitimate ERC20 tokens that take a transfer fee (like some rebasing tokens), causing DoS for users trying to use those tokens",
    "paths": [
      "Attempt to purchase bonds using a token that takes a transfer fee"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Missing access control on setReferrerFee",
    "locations": [
      "bases/BondBaseTeller.sol:88"
    ],
    "claim": "setReferrerFee allows any address to set their own referrer fee without verification, allowing frontends to set excessive fees",
    "impact": "Frontends can set high referrer fees (up to 50%) and steal value from users who don't verify the fee before purchasing",
    "paths": [
      "Call setReferrerFee(50000) before creating a bond purchase"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Unchecked callback return values",
    "locations": [
      "bases/BondBaseTeller.sol:196"
    ],
    "claim": "The callback function is called but only checks that payoutToken balance increased, not that the exact required amount was received",
    "impact": "A malicious callback can return less payout than required while the check only verifies balance increased (not the specific amount)",
    "paths": [
      "Deploy malicious callback contract that transfers less payout than required"
    ]
  },
  {
    "id": "F-006",
    "severity": "Low",
    "confidence": "low",
    "title": "Guardian parameter unused in Auth contract",
    "locations": [
      "bases/BondBaseTeller.sol:78",
      "BondFixedExpiryTeller.sol:52"
    ],
    "claim": "The guardian_ parameter is passed to Auth constructor but Auth only has owner and authority roles - no separate guardian role exists",
    "impact": "Documentation mentions 'guardian' required for certain functions but implementation only uses owner/authority, creating confusion and potential for misuse",
    "paths": []
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
