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
[
  {
    "id": "F-001",
    "severity": "Low",
    "confidence": "high",
    "title": "Output transfers silently underdeliver with fee-on-transfer or deceptive ERC20s",
    "locations": [
      "libraries/TokenTransfer.sol:13",
      "swapX2Y.sol:326",
      "swapY2X.sol:292",
      "liquidity.sol:466",
      "liquidity.sol:469",
      "limitOrder.sol:402",
      "limitOrder.sol:405",
      "flash.sol:142",
      "flash.sol:143",
      "iZiSwapPool.sol:526",
      "iZiSwapPool.sol:527"
    ],
    "claim": "All outbound token transfers only require `transfer()` to return success (or no returndata). The pool never verifies that the recipient actually received the nominal amount, so fee-on-transfer, rebasing-on-transfer, or otherwise deceptive tokens can pay out less than the amount the pool just finalized in state.",
    "impact": "Traders, LPs, limit-order users, flash borrowers, and the protocol fee receiver can receive less than the quoted or owed amount whenever a listed token skims or suppresses outbound transfers. The protocol has no on-chain signal that the payout was short.",
    "paths": [
      "Create or list a pool whose token charges transfer fees or otherwise underdelivers on outbound `transfer()`.",
      "Trigger a swap, collect, flash loan, or protocol-fee withdrawal that pays that token out.",
      "The transfer call succeeds, state is finalized, but the recipient receives fewer tokens than the nominal payout."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-002",
    "severity": "Medium",
    "confidence": "high",
    "title": "collect() and collectLimOrder() erase unpaid claims instead of reverting on shortfalls",
    "locations": [
      "liquidity.sol:460",
      "liquidity.sol:461",
      "liquidity.sol:463",
      "liquidity.sol:464",
      "limitOrder.sol:392",
      "limitOrder.sol:397",
      "limitOrder.sol:399",
      "limitOrder.sol:400",
      "iZiSwapPool.sol:320",
      "iZiSwapPool.sol:321"
    ],
    "claim": "Both collection paths decrement the user's stored claim before checking how many tokens the pool can actually pay, then clamp the transfer to the current balance. In `collectLimOrder()`, the module still returns and emits the pre-clamp amounts, so callers can be told they collected more than was actually transferred.",
    "impact": "If the pool is ever underfunded, the first claimer permanently loses the unpaid remainder instead of reverting and preserving the claim. Limit-order integrations can also overcredit users because the returned and emitted amounts may exceed the tokens actually sent.",
    "paths": [
      "The pool becomes short of token balances for any reason, such as rebasing tokens, asset loss, or prior misaccounted payouts.",
      "A user calls `collect()` or `collectLimOrder()` for the full amount owed.",
      "Storage is reduced immediately, only `min(claim, balance)` is transferred, and the unpaid remainder is irretrievably burned."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-003",
    "severity": "Low",
    "confidence": "high",
    "title": "enableFeeAmount() allows fee-tier parameters that disable core pool functionality",
    "locations": [
      "iZiSwapFactory.sol:88",
      "iZiSwapFactory.sol:91",
      "iZiSwapFactory.sol:106",
      "iZiSwapPool.sol:119",
      "liquidity.sol:336",
      "swapX2Y.sol:151",
      "swapX2Y.sol:166",
      "swapX2Y.sol:370",
      "swapY2X.sol:150",
      "swapY2X.sol:166",
      "swapY2X.sol:334"
    ],
    "claim": "The factory only checks `pointDelta > 0` and never bounds `fee` or `pointDelta`. A tier with `fee >= 1_000_000` makes swap math hit `1e6 - fee` as zero or underflow, reverting every swap. A tier with `pointDelta > 800000` collapses the usable price grid to a single point, so `mint()` can never satisfy `leftPt < rightPt` within the pool's allowed range.",
    "impact": "The owner can accidentally or deliberately register tiers that let users create pools with broken core functionality: some tiers cannot execute swaps at all, while others cannot accept LP liquidity.",
    "paths": [
      "Owner calls `enableFeeAmount()` with an out-of-range `fee` or `pointDelta`.",
      "A user creates a pool under that tier.",
      "Either swaps revert immediately (`fee >= 1_000_000`) or no valid liquidity range can ever be minted (`pointDelta > 800000`)."
    ],
    "round": 1,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-004",
    "severity": "Low",
    "confidence": "high",
    "title": "Unbounded defaultFeeChargePercent can make newly created pools revert on fee distribution",
    "locations": [
      "iZiSwapFactory.sol:79",
      "iZiSwapFactory.sol:118",
      "iZiSwapFactory.sol:134",
      "swapX2Y.sol:225",
      "swapX2Y.sol:288",
      "swapX2Y.sol:408",
      "swapX2Y.sol:452",
      "swapY2X.sol:248",
      "swapY2X.sol:389",
      "flash.sol:156"
    ],
    "claim": "The factory constructor and `modifyDefaultFeeChargePercent()` accept values above 100, and `newPool()` copies that value directly into each pool. When a liquidity-backed swap or flash later computes `feeAmount - chargedFeeAmount`, any inherited `feeChargePercent > 100` makes the subtraction underflow and revert.",
    "impact": "New pools can be deployed with a latent configuration bug that prevents normal fee-bearing trading or flash loans until the owner separately fixes each pool's `feeChargePercent`.",
    "paths": [
      "Owner sets `defaultFeeChargePercent` above 100.",
      "A user creates a new pool after the bad default is in place.",
      "The first swap path or flash loan that tries to distribute liquidity fees reverts on `feeAmount - chargedFeeAmount`."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-005",
    "severity": "Low",
    "confidence": "high",
    "title": "test/TestAddLimOrder.payCallback() lets arbitrary callers pull approved tokens from the encoded payer",
    "locations": [
      "test/TestAddLimOrder.sol:29",
      "test/TestAddLimOrder.sol:34",
      "test/TestAddLimOrder.sol:36",
      "test/TestAddLimOrder.sol:39"
    ],
    "claim": "`payCallback()` never verifies that `msg.sender` is the expected iZiSwap pool. Any caller can supply callback data with a victim as `payer` and use this helper to execute `transferFrom()` from that victim to itself.",
    "impact": "If this test helper is ever deployed outside an isolated test environment and users approve it, an attacker can directly steal the approved token balances.",
    "paths": [
      "The `TestAddLimOrder` helper is deployed and a user grants it ERC20 allowance.",
      "An attacker calls `payCallback()` directly with calldata encoding that user as `payer`.",
      "The helper transfers the victim's approved tokens to the attacker's address (`msg.sender`)."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  }
]

## This Round's Agent Outputs
### Agent: codex_1
```
[
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "high",
    "title": "Canonical pool creation is permanently front-runnable with an attacker-chosen initial price",
    "locations": [
      "iZiSwapFactory.sol:95",
      "iZiSwapPool.sol:128"
    ],
    "claim": "The factory lets any caller create the canonical CREATE2 pool for a `(tokenX, tokenY, fee)` tuple, and the CREATE2 salt excludes `currentPoint`. An attacker can therefore deploy the only valid pool first with an arbitrary `currentPoint`, while the pool constructor blindly trusts the factory-staged value.",
    "impact": "A launcher or integrator can be permanently forced onto a hostile initial price for the pair/fee. First LPs and naive downstream tooling can then add liquidity or route flow against a poisoned starting state, and the legitimate deployer cannot recreate the pool with the intended price.",
    "paths": [
      "Front-run a pending `newPool(tokenA, tokenB, fee, fairPoint)` transaction with `newPool(tokenA, tokenB, fee, hostilePoint)`.",
      "Pre-squat pools for predictable or undeployed token addresses, then let the real token contracts go live against the attacker-chosen starting point."
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Same-point limit-order fills are claim-priority raceable instead of time-priority settled",
    "locations": [
      "libraries/UserEarn.sol:46",
      "libraries/UserEarn.sol:171",
      "limitOrder.sol:166",
      "limitOrder.sol:194"
    ],
    "claim": "Per-user limit-order settlement is taken from shared point-level `earn/legacyEarn` on a first-updater basis. `updateUnlegacyOrder()` and `updateLegacyOrder()` do not preserve placement order, and `decLimOrderWithX/Y()` can be called with `delta=0`, so whichever owner updates first after a shared fill can consume the available point-level proceeds up to their own remaining size.",
    "impact": "A later order owner at the same point and in the same direction can MEV-steal fills that users would normally expect older resting orders to receive first. Passive limit orders are therefore vulnerable to having execution priority taken away unless the owner actively races to update after every fill.",
    "paths": [
      "Victim and attacker both rest same-direction orders at point `P`; a swap partially fills the aggregate point order; attacker immediately calls `decLimOrderWithX(P,0)` or `decLimOrderWithY(P,0)` first; victim updates later and finds shared earn already depleted.",
      "The same race exists after full clears through the `legacyEarn` path because `updateLegacyOrder()` also allocates shared proceeds to the first updater."
    ]
  },
  {
    "id": "F-008",
    "severity": "Low",
    "confidence": "high",
    "title": "Current-point limit orders can be taken through `addLimOrder` with zero swap fee",
    "locations": [
      "limitOrder.sol:229",
      "limitOrder.sol:253",
      "limitOrder.sol:299",
      "limitOrder.sol:306",
      "limitOrder.sol:330",
      "limitOrder.sol:377"
    ],
    "claim": "The immediate-cross branches in `addLimOrderWithX()` and `addLimOrderWithY()` match against opposite resting orders at the point price, but the caller only pays `order + costOffset`; no swap fee or protocol charge is added before funds are assigned to `earnAssign`.",
    "impact": "Whenever opposite resting orders exist at the current point, takers can avoid the pool's normal fee path by using `addLimOrder` plus `collectLimOrder` instead of `swap`. That makes fee capture optional for this flow and creates economically inconsistent routing around the protocol fee model.",
    "paths": [
      "If `sellingY > 0` at `currentPoint`, call `addLimOrderWithX(recipient, currentPoint, amountX, ...)`, receive `acquireY` in `earnAssign`, then withdraw it with `collectLimOrder(recipient, currentPoint, 0, acquireY, true)`.",
      "If `sellingX > 0` at `currentPoint`, the symmetric `addLimOrderWithY()` path acquires X with no swap fee before collection."
    ]
  }
]

```

### Agent: opencode_1
```
Let me read key contract files to search for new security vulnerabilities.
Let me look at more key files like interfaces and libraries:
Let me examine a few more key areas to identify additional vulnerabilities:
Now I have a comprehensive understanding of the codebase. Based on my analysis, I found several security vulnerabilities that are DIFFERENT from the known findings (F-001 through F-005). Let me compile my findings:
Based on my comprehensive audit of the iZiSwap-core contracts, here are my NEW findings (different from Known Findings F-001 through F-005):
```json
[
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "high",
    "title": "Oracle observation queue can be truncated leading to flash loan price manipulation",
    "locations": [
      "libraries/Oracle.sol:67-75"
    ],
    "claim": "The append function allows queue length increase only when currentIndex equals queueLen-1. If nextQueueLen is not reached, stale observations get overwritten in the circular queue without expanding, potentially allowing manipulation of TWAP prices if an attacker controls the timing of swaps near queue expansion.",
    "impact": "TWAP oracle readings can be manipulated if pool operators or attackers can trigger queue truncation through specific swap patterns, enabling flash loan attacks on protocols relying on TWAP oracles.",
    "paths": []
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "medium",
    "title": "modifyFeeChargePercent can be front-run to trap fees in pool",
    "locations": [
      "iZiSwapPool.sol:533-538"
    ],
    "claim": "The modifyFeeChargePercent function requires msg.sender == factory owner but does not validate the current feeChargePercent value. Setting 100% feeChargePercent causes all fees to be charged to miners with none left for liquidity provider distribution.",
    "impact": "A malicious or compromised factory owner can front-run pool operations to set feeChargePercent to 100%, trapping all swap fees as the owner receives chargedFeeAmount while feeScale remains unchanged, denying LP fee rewards.",
    "paths": []
  },
  {
    "id": "F-008",
    "severity": "High",
    "confidence": "high",
    "title": "Flash loan can drain pool by specifying amount exceeding balance",
    "locations": [
      "flash.sol:124-166",
      "flash.sol:139-143"
    ],
    "claim": "In flash(), actualAmountX/Y is computed as min(amountX/Y, balanceBefore). The pool transfers actualAmount to recipient, then charges fees on the original requested amount (amountX/Y), not actualAmount. If pool has insufficient balance after transfer, the fee check passes but pool may be left unable to collect.",
    "impact": "If pool lacks sufficient tokens, a malicious flash borrower can request amount > pool balance, receive actualAmount = balance, pay fees on full amount, but pool ends up undercollateralized since the borrower only returns actualAmount + fees while keeping the full loan.",
    "paths": []
  },
  {
    "id": "F-009",
    "severity": "Low",
    "confidence": "medium",
    "title": "newPool lacks deadline parameter allowing stale pool creation",
    "locations": [
      "iZiSwapFactory.sol:95-126"
    ],
    "claim": "newPool() has no deadline parameter and executes immediately. In high-traffic situations, if token prices shift significantly between transaction signing and execution, the pool may be created with an inappropriate initial currentPoint.",
    "impact": "Traders who submitted earlier may get worse prices than expected if the pool initializes at a stale point, causing unexpected slippage.",
    "paths": []
  },
  {
    "id": "F-010",
    "severity": "Low",
    "confidence": "high",
    "title": "Burn allows removing more liquidity than deposited due to point crossover",
    "locations": [
      "liquidity.sol:397-440",
      "libraries/Liquidity.sol:18-26"
    ],
    "claim": "The burn function computes refund amounts based on currentState at entry, but the state can change between computation and actual burn if swaps occur. The liquidity subtraction uses signed delta which could underflow if liquidityX adjustment is incorrect during point crossover.",
    "impact": "If state changes between burn call and execution, the computed refund amounts may be incorrect, potentially allowing withdrawal of more tokens than entitled or getting stuck state.",
    "paths": []
  },
  {
    "id": "F-011",
    "severity": "Medium",
    "confidence": "low",
    "title": "Swap callbacks can be reentrant with visswap through callback",
    "locations": [
      "swapX2Y.sol:328-331",
      "swapY2X.sol:293-297"
    ],
    "claim": "After token transfers in swap functions, the callback is invoked and then balance is checked. The swap function does not follow checks-effects-interactions pattern strictly as state is written before callback but the lock modifier prevents direct reentrancy. However, the callback can call back into the same pool through a different function entry point.",
    "impact": "A malicious callback could trigger nested swaps across multiple pools in a single transaction, potentially amplifying price impact calculations across the system.",
    "paths": []
  },
  {
    "id": "F-012",
    "severity": "Low",
    "confidence": "medium",
    "title": "expandObservationQueue allows DoS by setting huge queue length",
    "locations": [
      "iZiSwapPool.sol:476-482"
    ],
    "claim": "expandObservationQueue allows any address to expand the observation queue length. While there is a size limit (65535), setting a very large newNextQueueLen could increase gas costs for observe() calls and consume more storage.",
    "impact": "Anyone can expand the queue, potentially causing higher gas costs for the pool in observe() operations.",
    "paths": []
  }
]
```

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
