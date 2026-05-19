Below are findings from 2 agents auditing the same codebase,
plus accumulated findings from previous rounds.

You are the merge layer for a audit loop. You can inspect the source code when needed.

Your task is to read all findings from this round, merge them into the 
summary of distinct issues, compare that round summary against accumulated findings,
and keep new or materially improved findings in the updated list. And you are encouraged to find more based on these findings and source code.

If an issue already exists in accumulated findings, do not add a duplicate. 
Remove findings that are not defensible after checking the code.
Downgrade severity or confidence when the issue depends on unusual configuration or weak
assumptions. 
Treat each finding carefully.

## Accumulated Findings
None yet.

## This Round's Agent Outputs
### Agent: codex_1
```
[
  {
    "id": "F-001",
    "severity": "Medium",
    "confidence": "high",
    "title": "Outgoing payouts trust transfer() success without verifying how many tokens were actually delivered",
    "locations": [
      "libraries/TokenTransfer.sol:13",
      "swapX2Y.sol:326",
      "swapY2X.sol:292",
      "liquidity.sol:466",
      "limitOrder.sol:402",
      "flash.sol:142",
      "iZiSwapPool.sol:526"
    ],
    "claim": "All payout paths only check that the token call returned success (or empty returndata). They never verify the recipient's actual balance increase or the pool's post-transfer balance delta, so fee-on-transfer, rebasing, or malicious ERC20s can underdeliver while the AMM finalizes state as if the full nominal amount was paid.",
    "impact": "Swappers, LPs, limit-order users, flash borrowers, and the fee receiver can all receive less than quoted or owed. The missing verification also lets pool accounting drift away from real balances, creating hidden insolvency that later harms other users.",
    "paths": [
      "Create or use a pool where tokenX or tokenY is transfer-taxed or otherwise non-standard",
      "Trigger a swap, collect, flash, or protocol-fee withdrawal that pays that token out",
      "The token transfer succeeds but the recipient receives less than the amount the pool already accounted for"
    ]
  },
  {
    "id": "F-002",
    "severity": "Medium",
    "confidence": "high",
    "title": "collect() and collectLimOrder() burn claims before confirming the pool can actually pay them",
    "locations": [
      "liquidity.sol:460",
      "liquidity.sol:463",
      "limitOrder.sol:392",
      "limitOrder.sol:397",
      "limitOrder.sol:399"
    ],
    "claim": "Both collectors decrement the user's receivable in storage first and only afterward clamp the transfer to the pool's current token balance. If the contract is short, the unpaid remainder is erased instead of causing a revert.",
    "impact": "Any temporary shortfall becomes a permanent user loss for the first claimer. Once balances fall below liabilities, LP fees, withdrawn liquidity, or limit-order proceeds can be irreversibly burned by merely attempting to collect them.",
    "paths": [
      "Pool becomes underfunded because of taxed/rebasing/malicious token behavior or any other asset loss",
      "User calls collect() or collectLimOrder() for their full claim",
      "Storage is reduced by the requested amount, but only min(claim, current balance) is transferred"
    ]
  },
  {
    "id": "F-003",
    "severity": "Low",
    "confidence": "high",
    "title": "enableFeeAmount() accepts fee-tier parameters that can brick newly created pools",
    "locations": [
      "iZiSwapFactory.sol:88",
      "iZiSwapFactory.sol:91",
      "swapX2Y.sol:151",
      "swapX2Y.sol:166",
      "swapY2X.sol:150",
      "swapY2X.sol:166",
      "libraries/SwapMathX2Y.sol:45",
      "libraries/SwapMathX2Y.sol:106",
      "libraries/SwapMathX2YDesire.sol:42",
      "libraries/SwapMathX2YDesire.sol:128"
    ],
    "claim": "The factory does not bound either fee or pointDelta when enabling a tier. A fee of 1,000,000 or more makes swap fee denominators hit zero/underflow, and oversized pointDelta values push the X->Y math outside the range assumed by the custom a*b-based mulDivCeil helpers.",
    "impact": "The owner can accidentally or maliciously register fee tiers whose pools are unusable or revert on X->Y trades, permanently DoSing any market created under that tier.",
    "paths": [
      "Owner enables a tier with fee >= 1_000_000 or an oversized pointDelta",
      "A user creates a pool under that tier",
      "swapX2Y/swapX2YDesireY reverts because the fee math or X->Y range math breaks"
    ]
  },
  {
    "id": "F-004",
    "severity": "Low",
    "confidence": "high",
    "title": "defaultFeeChargePercent is unbounded, so newly created pools can inherit a fee split that always underflows",
    "locations": [
      "iZiSwapFactory.sol:79",
      "iZiSwapFactory.sol:118",
      "iZiSwapFactory.sol:134",
      "swapX2Y.sol:288",
      "swapY2X.sol:248",
      "flash.sol:156"
    ],
    "claim": "The factory constructor and modifyDefaultFeeChargePercent() accept values above 100, but pool fee accounting later computes feeAmount - chargedFeeAmount. Any newly created pool that inherits feeChargePercent > 100 will underflow as soon as swap or flash fees are distributed.",
    "impact": "A bad factory configuration silently plants a latent DOS into future pools: they deploy successfully, but their first fee-bearing swap or flash loan reverts.",
    "paths": [
      "Owner sets defaultFeeChargePercent above 100",
      "A new pool is created afterward",
      "The first swap or flash with nonzero fees reverts during fee accounting"
    ]
  },
  {
    "id": "F-005",
    "severity": "Low",
    "confidence": "high",
    "title": "TestAddLimOrder.payCallback() can be called by any address to pull approved tokens from the payer",
    "locations": [
      "test/TestAddLimOrder.sol:29"
    ],
    "claim": "Unlike the other callback helpers, payCallback() never checks that msg.sender is the expected pool. Any caller can supply arbitrary callback data and use existing ERC20 allowances to transfer tokens from payer to itself.",
    "impact": "If this helper is ever deployed outside isolated tests and users approve it, an attacker can directly steal the approved token balances.",
    "paths": [
      "Victim approves TestAddLimOrder for tokenX and/or tokenY",
      "Attacker calls payCallback() directly with the victim as payer",
      "safeTransferFrom() moves the victim's approved tokens to the attacker-controlled caller"
    ]
  }
]

```

### Agent: opencode_1
```
Based on my analysis of the iZiSwap-core contracts, I've identified several security vulnerabilities. Here's my findings:

```json
[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Division by zero when fee = 1,000,000",
    "locations": [
      "swapY2X.sol:150",
      "swapY2X.sol:166",
      "swapY2X.sol:167",
      "swapY2X.sol:225",
      "swapY2X.sol:237",
      "swapY2X.sol:238",
      "swapY2X.sol:334",
      "swapY2X.sol:388",
      "swapX2Y.sol:151",
      "swapX2Y.sol:166",
      "swapX2Y.sol:167",
      "swapX2Y.sol:204",
      "swapX2Y.sol:219",
      "swapX2Y.sol:220",
      "swapX2Y.sol:267",
      "swapX2Y.sol:278",
      "swapX2Y.sol:279",
      "swapX2Y.sol:370",
      "swapX2Y.sol:407",
      "swapX2Y.sol:451"
    ],
    "claim": "When fee = 1,000,000 (100%), the expression (1e6 - fee) evaluates to 0, causing division by zero in fee calculations",
    "impact": "A pool created with fee = 1,000,000 would cause all swaps to revert due to division by zero, potentially trapping liquidity",
    "paths": [
      "1. Factory owner enables fee amount 1000000 via enableFeeAmount()",
      "2. User creates pool with fee = 1000000",
      "3. Any swap attempt fails with division by zero"
    ]
  },
  {
    "id": "F-002",
    "severity": "Medium",
    "confidence": "high",
    "title": "Useless require check allows any feeChargePercent including malicious values",
    "locations": [
      "iZiSwapPool.sol:535"
    ],
    "claim": "The check require(newFeeChargePercent >= 0, 'FP0') is always true since uint24 is an unsigned integer that cannot be negative",
    "impact": "While the upper bound is checked (100%), the meaningless lower check could mask logic errors or be confusing. More critically, feeChargePercent can be set to 100% meaning all fees go to miners leaving nothing for protocol",
    "paths": [
      "1. Factory owner calls modifyFeeChargePercent(100)",
      "2. All swap fees now go entirely to miners, protocol earns nothing"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Missing access control allows theft of collected fees",
    "locations": [
      "iZiSwapPool.sol:524"
    ],
    "claim": "collectFeeCharged() only checks that msg.sender equals factory's chargeReceiver, but if chargeReceiver is changed to address(0), anyone can call it to steal accumulated fees",
    "impact": "If modifyChargeReceiver is called with address(0), anyone can drain all accumulated protocol fees",
    "paths": [
      "1. Factory owner calls modifyChargeReceiver(address(0))",
      "2. Attacker calls collectFeeCharged() to steal all fees"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "Token pair order check can be bypassed in newPool",
    "locations": [
      "iZiSwapFactory.sol:102"
    ],
    "claim": "The constructor checks token

```

## Output
Return the COMPLETE updated findings list as a JSON array.

Each element must have:
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

Output ONLY valid JSON. No markdown. No prose.
