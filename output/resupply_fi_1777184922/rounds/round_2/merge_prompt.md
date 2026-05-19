Below are findings and vulnerability signals from 1 agents auditing the same codebase,
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
[
  {
    "id": "F-001",
    "severity": "High",
    "confidence": "high",
    "title": "Oracle decimal scaling is ignored, so non-18-decimal feeds misprice collateral by orders of magnitude",
    "locations": [
      "src/interfaces/IOracle.sol:5",
      "src/protocol/pair/ResupplyPairCore.sol:573",
      "src/protocol/ResupplyPair.sol:176"
    ],
    "claim": "The pair hardcodes exchange-rate inversion as `1e36 / oraclePrice` and never normalizes by `IOracle.decimals()`, even though the oracle interface exposes a decimals field and `setOracle()` accepts arbitrary replacement feeds. Any oracle returning prices in a scale other than 18 decimals will distort the collateral/debt conversion by a power-of-ten factor.",
    "impact": "Borrow, solvency, redemption, and liquidation math can all be wrong by orders of magnitude. Depending on the oracle scale, healthy positions can be liquidated or blocked from withdrawing, or collateral can be overvalued enough for borrowers to mint far more debt than intended, leaving the pair insolvent.",
    "paths": [
      "A pair is deployed with, or later updated to, an oracle whose `getPrices()` output is not 18-decimal scaled.",
      "`_updateExchangeRate()` computes `exchangeRate = 1e36 / price` without using `IOracle.decimals()`.",
      "The distorted exchange rate propagates into `_isSolvent()`, borrow limits, redemptions, and liquidations."
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Unchecked Convex staking results can leave credited collateral unstaked and later lock withdrawals/liquidations",
    "locations": [
      "src/protocol/ResupplyPair.sol:399",
      "src/protocol/ResupplyPair.sol:409",
      "src/protocol/ResupplyPair.sol:421",
      "src/protocol/pair/ResupplyPairCore.sol:713",
      "src/protocol/pair/ResupplyPairCore.sol:769"
    ],
    "claim": "When Convex mode is enabled, the pair credits user collateral first and then calls `IConvexStaking.deposit(...)` without checking its boolean return value. `totalCollateral()` only counts the reward-contract stake balance, so if a Convex deposit returns `false` or stakes less than expected, the pair's accounting assumes collateral was staked while later exits try to withdraw shares that never reached Convex.",
    "impact": "User collateral can become effectively stuck: withdrawals, liquidations, or pool migrations can revert because `_unstakeUnderlying()` pulls from the reward contract while the missing collateral remains idle in the pair. This creates accounting divergence and can permissionlessly DoS collateral exits for affected positions.",
    "paths": [
      "A borrower adds collateral while `convexPid != 0`, or the owner migrates pools with `_updateConvexPool()`.",
      "The Convex `deposit(..., true)` call returns `false` or under-stakes, but the pair ignores the result and still keeps the higher `_userCollateralBalance`.",
      "Later `_removeCollateral()` or pool migration calls `_unstakeUnderlying()` for the credited amount, but the reward contract balance is lower than expected, causing the operation to fail."
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  }
]

## This Round's Agent Outputs
### Agent: codex
```
[
  {
    "id": "F-002",
    "severity": "Medium",
    "confidence": "high",
    "title": "Accrued reward tokens can be stolen after any zero-debt period",
    "locations": [
      "src/protocol/RewardDistributorMultiEpoch.sol:162",
      "src/protocol/RewardDistributorMultiEpoch.sol:200",
      "src/protocol/pair/ResupplyPairCore.sol:325",
      "src/protocol/pair/ResupplyPairCore.sol:727"
    ],
    "claim": "Reward accrual is only incorporated into `global_reward_integral` when `_totalRewardShares() > 0`, but rewards can still be claimed into the pair while borrow shares are zero. Because `reward_remaining` is left unchanged in that state, the next borrower can open a tiny position and then claim the entire backlog of CRV/CVX/gov rewards that accrued while the pair had no debt shares.",
    "impact": "Any rewards earned during periods with zero outstanding borrows become claimable by the first later borrower instead of being isolated or discarded. If collateral remains staked while no debt exists, a minimal borrower can permissionlessly siphon the full accumulated incentive balance.",
    "paths": [
      "Users deposit collateral through `addCollateralVault`/`addCollateral`, so collateral is staked even when `totalBorrow.shares == 0`.",
      "A checkpoint/claim pulls external rewards into the pair while `_totalRewardShares() == 0`, so `_calcRewardIntegral` skips accounting them and does not advance `reward_remaining`.",
      "An attacker opens the first small borrow after that zero-debt period and then calls `getReward`, causing the entire previously accrued balance to be distributed over their fresh borrow shares."
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "Convex pool migration mishandles the sentinel `pid == 0` and can orphan all collateral",
    "locations": [
      "src/protocol/ResupplyPair.sol:382",
      "src/protocol/ResupplyPair.sol:399",
      "src/protocol/ResupplyPair.sol:402",
      "src/protocol/ResupplyPair.sol:421"
    ],
    "claim": "`convexPid == 0` is treated everywhere else as 'do not stake', but `_updateConvexPool` still migrates by reading `poolInfo(currentPid)` and blindly depositing `stakedBalance` into `_pid`, including when `_pid == 0`; it also ignores any collateral already sitting locally when migrating from `0` to a live pool. After the update, `totalCollateral()` switches accounting modes based only on `convexPid`, so collateral can remain staked or remain local while the accounting path looks somewhere else.",
    "impact": "A normal admin pool-change can make the pair believe collateral is gone, freeze withdrawals/liquidations, and leave live positions falsely insolvent or permanently locked until an out-of-band recovery is performed. This is protocol-level fund lockup, not just a cosmetic accounting issue.",
    "paths": [
      "If the owner calls `setConvexPool(0)` to disable staking, `_updateConvexPool` withdraws from the old pool and then immediately deposits the same collateral into pool `0`, but sets `convexPid = 0`; `totalCollateral()` then reads only the local wallet balance and ignores the still-staked funds.",
      "If the pair starts with `convexPid == 0` and already holds local collateral, calling `setConvexPool(nonZeroPid)` migrates only `stakedBalance` from the old rewards contract and never stakes the local collateral; afterwards `totalCollateral()` reads only Convex stake and ignores the local holdings."
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "low",
    "title": "Redemption protocol fees are double-counted unless the external handler burns the full input amount",
    "locations": [
      "src/protocol/pair/ResupplyPairCore.sol:931",
      "src/protocol/pair/ResupplyPairCore.sol:932",
      "src/protocol/pair/ResupplyPairCore.sol:952",
      "src/protocol/ResupplyPair.sol:346"
    ],
    "claim": "On redemption, the pair adds `protocolFee` to `claimableOtherFees` and later mints that amount again in `withdrawFees`, but the inline accounting comment says the protocol-fee portion of the redeemed stablecoin 'is not burned'. If the redemption flow actually leaves that fee amount unburned, `withdrawFees` mints a second copy of the same protocol fee.",
    "impact": "A handler implementation that burns only `debtReduction` rather than the full redemption input would cause every redemption to inflate stable supply by `protocolFee`, creating unbacked protocol fees and cumulative insolvency over time.",
    "paths": [
      "A redemption calls `redeemCollateral`, which computes `protocolFee` and records it in `claimableOtherFees`.",
      "The external redemption handler burns only `debtReduction` because the pair comment states the protocol-fee portion is 'not burned'.",
      "Later, `withdrawFees` mints `claimableOtherFees` again to the fee deposit contract, duplicating the already-unburned protocol-fee amount."
    ]
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
