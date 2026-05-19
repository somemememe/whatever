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
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "high",
    "title": "Permissionless pool creation lets attackers permanently squat pair/fee slots and choose the initial price",
    "locations": [
      "iZiSwapFactory.sol:95",
      "iZiSwapFactory.sol:101",
      "iZiSwapFactory.sol:105",
      "iZiSwapFactory.sol:110",
      "iZiSwapPool.sol:128",
      "iZiSwapPool.sol:149"
    ],
    "claim": "`newPool()` is permissionless, only rejects identical token addresses, and uses a CREATE2 salt keyed solely by `(tokenX, tokenY, fee)`. Because the factory never checks that either token is an already deployed contract and the salt omits `currentPoint`, any third party can deploy the sole canonical pool for that tuple first with arbitrary staged parameters, while the pool constructor blindly accepts the staged `currentPoint`.",
    "impact": "Pair launches can be front-run or pre-squatted before token deployment. The intended deployer cannot recreate the canonical pool with the desired initialization, and downstream users or integrators may be pushed onto an attacker-chosen starting price or forced to use a different fee tier.",
    "paths": [
      "Front-run a pending `newPool(tokenA, tokenB, fee, fairPoint)` transaction with `newPool(tokenA, tokenB, fee, hostilePoint)`.",
      "Pre-create pools for predictable future token addresses and chosen fee tiers before the real token contracts go live."
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "high",
    "title": "Same-point limit orders settle by first claim rather than order time",
    "locations": [
      "libraries/UserEarn.sol:38",
      "libraries/UserEarn.sol:46",
      "libraries/UserEarn.sol:60",
      "limitOrder.sol:166",
      "limitOrder.sol:177",
      "limitOrder.sol:194",
      "limitOrder.sol:205"
    ],
    "claim": "Per-user settlement at a point follows the documented `first claim first earn` rule. `updateUnlegacyOrder()` and `updateLegacyOrder()` draw from shared point-level `earn` or `legacyEarn`, and `decLimOrderWithX/Y()` allow `delta = 0`, so any owner at that point can update after a shared fill without cancelling size. The first updater consumes as much of the shared proceeds as their own remaining order allows, regardless of placement order.",
    "impact": "A later order owner at the same point and in the same direction can race older orders and capture fills that many limit-order users would expect to settle FIFO. Passive same-price orders are therefore MEV-stealable unless owners actively update after fills.",
    "paths": [
      "Victim and attacker both rest same-direction orders at point `P`; a swap partially fills the aggregate point order; attacker immediately calls `decLimOrderWithX(P,0)` or `decLimOrderWithY(P,0)` first; victim updates later and finds the shared proceeds depleted.",
      "The same race exists after a full clear through the legacy path because `updateLegacyOrder(0, ...)` also assigns shared `legacyEarn` to the first updater."
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-008",
    "severity": "Low",
    "confidence": "medium",
    "title": "Crossing resting limit orders via addLimOrder bypasses swap fee accounting",
    "locations": [
      "limitOrder.sol:229",
      "limitOrder.sol:253",
      "limitOrder.sol:257",
      "limitOrder.sol:276",
      "limitOrder.sol:301",
      "limitOrder.sol:306",
      "limitOrder.sol:330",
      "limitOrder.sol:334",
      "limitOrder.sol:353",
      "limitOrder.sol:379",
      "swapX2Y.sol:151",
      "swapX2Y.sol:161",
      "swapY2X.sol:150",
      "swapY2X.sol:161"
    ],
    "claim": "`addLimOrderWithX/Y()` immediately match against opposite resting point orders and credit the taker through `earnAssign`, but the callback only requests the matched principal plus any residual order amount. Unlike the swap paths that consume the same point orders, these branches never compute `feeAmount`, `chargedFeeAmount`, or update LP fee scales for the matched portion.",
    "impact": "Whenever resting opposite orders exist, a taker can route through `addLimOrder` plus `collectLimOrder` instead of `swap` and pay no pool fee or protocol charge on that matched flow. Fee capture becomes optional for order-to-order crossing, creating inconsistent execution economics.",
    "paths": [
      "If opposite resting orders exist at `currentPoint`, call `addLimOrderWithX()` or `addLimOrderWithY()` there with just enough input to consume them, then withdraw the acquired token with `collectLimOrder()`.",
      "Repeat the same pattern whenever new resting opposite orders appear, using `addLimOrder` as a fee-free taker path instead of the normal swap entrypoint."
    ],
    "round": 2,
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
    "id": "F-010",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Oracle prices can be moved across zero-liquidity gaps for near-zero cost",
    "locations": [
      "swapX2Y.sol:258",
      "swapY2X.sol:209",
      "swapX2Y.sol:310",
      "iZiSwapPool.sol:458"
    ],
    "claim": "Both swap directions jump `state.currentPoint` directly to the next initialized point or boundary whenever `st.liquidity == 0`, without consuming trader input for the skipped range. If the swap changes the point, that new point is then written into the observation ring and exposed through `observe()`.",
    "impact": "Sparse-liquidity pools can have their reported price and TWAP shifted much more cheaply than the apparent point distance suggests. Any downstream integration that treats `observe()` as a robust oracle can be manipulated after the attacker pushes the pool into an empty gap or trades through one.",
    "paths": [
      "move the pool into or near a gap with no active liquidity",
      "perform a small swap that free-jumps across the gap and only pays at the first active point reached",
      "let `observe()` or a TWAP consumer read the manipulated point history"
    ]
  },
  {
    "id": "F-009",
    "severity": "Low",
    "confidence": "medium",
    "title": "Oversized flash-fee donations can push fee-growth counters into overflow and wedge fee-accruing paths",
    "locations": [
      "flash.sol:133",
      "flash.sol:158",
      "flash.sol:163",
      "swapX2Y.sol:228",
      "swapY2X.sol:251",
      "libraries/Liquidity.sol:53"
    ],
    "claim": "Position settlement explicitly treats `feeScaleX_128/feeScaleY_128` as wrapping counters, but every accrual site updates them with checked `+`. Because `flash()` charges fees on the requested amount even when `actualAmountX/Y` is smaller, a caller can inject an outsized fee into a very low-liquidity pool and drive a fee scale near `uint256.max`, after which the next accrual reverts instead of wrapping.",
    "impact": "Once a side's fee-growth counter is near the limit, later swaps or flashes that accrue fees on that side can start reverting, leaving that side of the pool effectively DoSed. The cheapest path is on low-liquidity pools and on pools that include an attacker-controlled high-supply token.",
    "paths": [
      "find or seed a pool with tiny `state.liquidity`",
      "call `flash()` with an enormous `amountX` or `amountY` so the computed fee is huge even if the pool cannot lend that much",
      "repay only the fee in the callback and push the fee-growth counter near `2^256 - 1`",
      "trigger one more fee-accruing swap or flash on the same side and hit checked overflow"
    ]
  },
  {
    "id": "F-011",
    "severity": "Low",
    "confidence": "high",
    "title": "Resting limit-order swap fills ignore the configured protocol-fee split",
    "locations": [
      "iZiSwapPool.sol:104",
      "swapX2Y.sol:172",
      "swapX2Y.sol:371",
      "swapY2X.sol:172",
      "swapY2X.sol:335"
    ],
    "claim": "The pool documents `feeChargePercent` as the percentage charged from trader fees, but the swap branches that fill resting limit orders add the full `feeAmount` to `totalFeeXCharged/totalFeeYCharged` instead of applying `feeChargePercent`. Only the liquidity-crossing branches respect the configured split.",
    "impact": "Whenever a trade executes against resting limit orders at the current point, the configured charge receiver captures 100% of the fee regardless of the pool's advertised fee split. This is an economic extraction path that underpays the non-protocol side of those fills.",
    "paths": [
      "leave resting limit orders at the current point",
      "execute `swapX2Y`, `swapY2X`, `swapX2YDesireY`, or `swapY2XDesireX` so the trade is satisfied by the limit-order branch"
    ]
  },
  {
    "id": "F-012",
    "severity": "Informational",
    "confidence": "high",
    "title": "The public `orderOrEndpoint` getter is keyed by a normalized index, not by the documented point",
    "locations": [
      "iZiSwapPool.sol:82",
      "libraries/OrderOrEndpoint.sol:10",
      "interfaces/IiZiSwapPool.sol:432"
    ],
    "claim": "Internally, `orderOrEndpoint` is stored at `point / pointDelta`, but the pool exposes the raw mapping getter and the interface documents it as if callers should pass the actual point. A caller that supplies the documented point receives incorrect data unless it manually normalizes the key first.",
    "impact": "Integrations that inspect initialized points or resting-order presence through this getter can silently miss live state, leading to incomplete monitoring, bad quotes, or unsafe routing logic built on incorrect point availability.",
    "paths": [
      "query `orderOrEndpoint(realPoint)` through the public getter",
      "receive `0` for many initialized points unless the caller pre-divides by `pointDelta`"
    ]
  }
]

```

### Agent: opencode_1
```
[
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "medium",
    "title": "No deadline validation in swap and limit order operations",
    "locations": [
      "swapX2Y.sol:122-333",
      "swapY2X.sol:123-298",
      "limitOrder.sol:229-303",
      "limitOrder.sol:306-381"
    ],
    "claim": "All swap and limit order functions lack deadline parameter validation",
    "impact": "Users' transactions may be executed at significantly later block times with unfavorable prices, as front-running or MEV extractors can hold and execute transactions at worst times. No time-based expiry prevents users from canceling stale orders.",
    "paths": [
      "User submits swap transaction with favorable price at time T",
      "Block timestamp increases significantly before execution",
      "Pool state changes (price moves unfavorably)",
      "Transaction executes at new price without user consent"
    ]
  },
  {
    "id": "F-010",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Missing reentrancy guard on collectFeeCharged function",
    "locations": [
      "iZiSwapPool.sol:524-530"
    ],
    "claim": "collectFeeCharged lacks the lock modifier that other state-modifying functions use",
    "impact": "The function transfers tokens and resets fee counters without reentrancy protection, enabling potential reentrancy attacks if the token transfer triggers a callback to the pool.",
    "paths": [
      "collectFeeCharged called",
      "Token transfer triggers callback (e.g., ERC777 token)",
      "Callback can call collectFeeCharged again in same transaction",
      "May cause inconsistent state or drain fees"
    ]
  },
  {
    "id": "F-011",
    "severity": "Low",
    "confidence": "medium",
    "title": "Unchecked observation queue expansion",
    "locations": [
      "iZiSwapPool.sol:476-482"
    ],
    "claim": "expandObservationQueue has no access control and no maximum limit validation",
    "impact": "Any user can expand the oracle queue size at any time, potentially causing unbounded gas consumption for future observe calls and DoS on the pool.",
    "paths": [
      "User calls expandObservationQueue with large newNextQueueLen",
      "Queue expands without validation of max size",
      "Future observe() calls consume excessive gas"
    ]
  },
  {
    "id": "F-012",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Fee charge percent can be set to zero, disincentivizing liquidity provision",
    "locations": [
      "iZiSwapPool.sol:535-536",
      "iZiSwapFactory.sol:134-136"
    ],
    "claim": "modifyFeeChargePercent allows setting 0% fee charge without lower bound validation",
    "impact": "Factory owner or pool owner can set feeChargePercent to 0 after pools have liquidity, effectively redirecting all fees to chargeReceiver while liquidity providers receive nothing. This breaks the economic model for existing LPs.",
    "paths": [
      "Pool accumulates significant liquidity",
      "Owner calls modifyFeeChargePercent(0)",
      "All swap fees go to chargeReceiver, LPs receive zero fee growth"
    ]
  },
  {
    "id": "F-013",
    "severity": "Low",
    "confidence": "medium",
    "title": "Dust amounts lost in collect due to min() with balance",
    "locations": [
      "liquidity.sol:463-464",
      "liquidity.sol:469-470",
      "limitOrder.sol:399-406"
    ],
    "claim": "collect functions use balance check that can silently reduce withdrawn amounts to available balance",
    "impact": "If token balance is less than owed amount (due to prior transfers or rounding), users receive less than their claim without any error or notification. This can lead to gradual loss of earned fees over time.",
    "paths": [
      "User has claimable fees in pool",
      "Pool balance becomes less than owed (e.g., transfer out, rounding errors)",
      "collect returns min(balance, owed)",
      "User loses the difference silently"
    ]
  },
  {
    "id": "F-014",
    "severity": "Low",
    "confidence": "low",
    "title": "Potential timestamp overflow in Oracle for old observations",
    "locations": [
      "Oracle.sol:98-105"
    ],
    "claim": "Oracle lte() function uses unchecked arithmetic that wraps around for very old timestamps",
    "impact": "If observation timestamps exceed 2^32 seconds (~136 years from epoch), the circular buffer comparison could fail, potentially returning incorrect oracle data.",
    "paths": [
      "Pool operates for extended period (>136 years)",
      "Timestamp wraps around in comparison",
      "Oracle returns wrong observations"
    ]
  },
  {
    "id": "F-015",
    "severity": "Low",
    "confidence": "low",
    "title": "Missing slippage protection in swap functions",
    "locations": [
      "swapX2Y.sol:123-333",
      "swapX2Y.sol:336-498",
      "swapY2X.sol:123-298",
      "swapY2X.sol:301-443"
    ],
    "claim": "Swap functions have no minimum output amount or slippage parameter",
    "impact": "Traders cannot specify maximum input or minimum output amounts, leaving them vulnerable to sandwich attacks and price impact. No slippage parameters means transactions can execute at arbitrarily bad rates.",
    "paths": [
      "User calls swap with large amount",
      "Attacker front-runs with large swap",
      "Price moves significantly",
      "User's swap executes at worse price with no protection"
    ]
  },
  {
    "id": "F-016",
    "severity": "Low",
    "confidence": "medium",
    "title": "Flash loan callback can receive more than requested amount without verification",
    "locations": [
      "flash.sol:139-143",
      "flash.sol:149-153"
    ],
    "claim": "flash() transfers actualAmount based on available balance, not requested amount, and callback receives fee based on requested amount",
    "impact": "If requested amount exceeds pool balance, the recipient gets less than requested but still pays fees on full requested amount. Additionally, the paidX/paidY calculation doesn't verify the actual transferred amounts match expectations.",
    "paths": [
      "User calls flash with amountX > pool balance",
      "actualAmountX = min(requested, balance)",
      "User pays fee on full requested amount",
      "Recipient receives less but pays full fee"
    ]
  },
  {
    "id": "F-017",
    "severity": "Low",
    "confidence": "low",
    "title": "No validation that fee2pointDelta mapping remains non-zero after enableFeeAmount",
    "locations": [
      "iZiSwapFactory.sol:88-92"
    ],
    "claim": "enableFeeAmount allows any positive pointDelta without validation of its relationship to pool functionality",
    "impact": "Owner can enable arbitrary fee/pointDelta pairs that might not provide meaningful price granularity, potentially creating pools with very wide tick spacing that don't function properly as trading venues.",
    "paths": [
      "Owner calls enableFeeAmount(1, 1)",
      "User creates pool with this fee tier",
      "Pool has inappropriate tick spacing for the fee"
    ]
  },
  {
    "id": "F-018",
    "severity": "Low",
    "confidence": "medium",
    "title": "Stale data persistence after liquidity burn leaves zero balance points",
    "locations": [
      "liquidity.sol:166-198"
    ],
    "claim": "Point data deletion happens before verifying liquidity fully burned to zero",
    "impact": "If there's any rounding or edge case, point data might be deleted while some microscopic liquidity remains, causing inconsistent pool state and potential future calculation errors.",
    "paths": [
      "User burns liquidity",
      "Point data deleted despite incomplete burn due to rounding",
      "Future operations read stale or incorrect point data"
    ]
  }
]

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
