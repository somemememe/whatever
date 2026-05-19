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
    "id": "F-002",
    "severity": "Medium",
    "confidence": "high",
    "title": "Rewards claimed while no borrow shares exist become permanently stranded in the pair",
    "locations": [
      "src/protocol/RewardDistributorMultiEpoch.sol:162",
      "src/protocol/RewardDistributorMultiEpoch.sol:200",
      "src/protocol/RewardDistributorMultiEpoch.sol:302",
      "src/protocol/pair/ResupplyPairCore.sol:321",
      "src/protocol/pair/ResupplyPairCore.sol:325"
    ],
    "claim": "Reward accrual is only added to `global_reward_integral` when `_totalRewardShares() > 0`, but `_checkpoint()` still calls `_fetchIncentives()` and `_calcRewardIntegral()` still updates `reward_remaining = bal` even when reward shares are zero. Because `getReward` is publicly callable and `totalRewardShares` is just `totalBorrow.shares`, any rewards fetched during a zero-debt period are marked as already-accounted without increasing any user/global integral, so the backlog can never be distributed later.",
    "impact": "CRV/CVX/governance rewards accrued while collateral remains staked but no borrows exist can be permanently trapped in the pair. This causes real value loss to the reward program/borrower set, and it is permissionless because any caller can trigger a checkpoint or `getReward` during the zero-share window.",
    "paths": [
      "Collateral remains staked in Convex while `totalBorrow.shares == 0`.",
      "External rewards accrue and any caller triggers `getReward`, `earned`, or another checkpoint path, which calls `claimRewards(address(this))`.",
      "`_calcRewardIntegral` skips integral growth because `_totalRewardShares() == 0` but still stores the fetched balance in `reward_remaining`.",
      "When borrowing later resumes, only rewards above that stored balance are distributable; the earlier fetched balance remains stuck in the pair with no recovery path."
    ],
    "round": 2,
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
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "Convex pool migration mishandles the sentinel `pid == 0` and can orphan all collateral",
    "locations": [
      "src/protocol/ResupplyPair.sol:382",
      "src/protocol/ResupplyPair.sol:386",
      "src/protocol/ResupplyPair.sol:399",
      "src/protocol/ResupplyPair.sol:402",
      "src/protocol/ResupplyPair.sol:421"
    ],
    "claim": "`convexPid == 0` is treated elsewhere as 'do not stake', but `_updateConvexPool()` always reads `poolInfo(currentPid)`, withdraws only the old reward-contract balance, and then blindly deposits `stakedBalance` into `_pid`, including when `_pid == 0`. It also ignores any collateral already sitting locally when migrating from `0` to a live pool. Since `totalCollateral()` switches between local-balance and reward-contract accounting based only on `convexPid`, changing pools across the sentinel can make the contract look in the wrong place for essentially all collateral.",
    "impact": "An owner pool update can make the pair believe collateral vanished, causing withdrawals and liquidations to revert or positions to appear insolvent even though the tokens still exist somewhere else. This is a protocol-level lockup/orphaning risk for all live collateral in the pair.",
    "paths": [
      "If the owner calls `setConvexPool(0)` to disable staking, `_updateConvexPool()` withdraws from the old rewards contract and then deposits the same amount into Convex pool `0`, but sets `convexPid = 0`; afterwards `totalCollateral()` reads only the pair's local collateral balance and ignores the still-staked funds.",
      "If the pair currently has `convexPid == 0` and already holds local collateral, calling `setConvexPool(nonZeroPid)` migrates only `stakedBalance` read from `poolInfo(0)` and never stakes the pair's local holdings; afterwards `totalCollateral()` reads only the Convex reward balance and ignores the locally held collateral.",
      "Any subsequent withdrawal, liquidation, or solvency path that relies on `totalCollateral()` / `_unstakeUnderlying()` can then fail against the mismatched accounting location."
    ],
    "round": 2,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "Unconditional reward claiming can globally freeze borrowing, repayments, withdrawals, and liquidations",
    "locations": [
      "src/protocol/RewardDistributorMultiEpoch.sol:224",
      "src/protocol/RewardDistributorMultiEpoch.sol:226",
      "src/protocol/pair/ResupplyPairCore.sol:321",
      "src/protocol/pair/ResupplyPairCore.sol:599",
      "src/protocol/pair/ResupplyPairCore.sol:833"
    ],
    "claim": "Every borrower checkpoint unconditionally calls `IResupplyRegistry(registry).claimRewards(address(this))`. Checkpoints sit inside `_syncUserRedemptions()` and `_repay()`, which are reached by `isSolvent`-gated borrow/collateral flows, normal repayments, and liquidations. As a result, any revert in the registry reward-claim path bricks core pair operations even though reward collection is ancillary bookkeeping.",
    "impact": "If the reward claimer, registry hook, or downstream reward source starts reverting, active borrowers can be unable to borrow, remove collateral, repay, repay with collateral, or be liquidated. That can trap user positions and let insolvencies persist because liquidation is blocked by an unrelated reward failure.",
    "paths": [
      "`borrow`, `removeCollateral*`, `leveragedPosition`, and `repayWithCollateral` all execute the `isSolvent` modifier, which calls `_syncUserRedemptions()` -> `_checkpoint()` -> `_fetchIncentives()` -> external `claimRewards` before the main action completes.",
      "`repay` and the liquidation path both call `_repay()`, which also checkpoints the borrower before updating debt and therefore hits the same external reward-claim dependency.",
      "If `claimRewards(address(this))` reverts for any reason, those state-changing entrypoints revert as well, causing a pair-wide DoS for debt management and liquidations."
    ],
    "round": 3,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-007",
    "severity": "High",
    "confidence": "medium",
    "title": "Zero oracle prices cause division-by-zero reverts across critical pair flows",
    "locations": [
      "src/protocol/pair/ResupplyPairCore.sol:573",
      "src/protocol/pair/ResupplyPairCore.sol:688",
      "src/protocol/pair/ResupplyPairCore.sol:955",
      "src/protocol/pair/ResupplyPairCore.sol:1001"
    ],
    "claim": "`_updateExchangeRate()` computes `1e36 / IOracle(...).getPrices(...)` without checking that the oracle returned a non-zero price. If the configured oracle ever returns `0` instead of reverting, the division hard-reverts every caller that refreshes the exchange rate.",
    "impact": "A zero oracle answer can halt borrowing, leveraged positions, redemptions, liquidations, and collateral withdrawals for borrowers that still have debt. This can trap positions and block liquidations during exactly the period when the price feed is unhealthy.",
    "paths": [
      "The configured oracle or one of its downstream feeds returns `0` for `getPrices(address(collateral))`.",
      "Any call path that executes `_updateExchangeRate()`—including `borrow`, `leveragedPosition`, `repayWithCollateral`, `redeemCollateral`, `liquidate`, and collateral removal for users with outstanding debt—reverts on division by zero.",
      "Because solvency updates and liquidation both depend on a fresh exchange rate, active positions can become unmanageable until the oracle stops returning zero."
    ],
    "round": 3,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-009",
    "severity": "Low",
    "confidence": "medium",
    "title": "Share-refactor floor rounding can leak small amounts of debt and leave unowned borrow shares",
    "locations": [
      "src/protocol/pair/ResupplyPairCore.sol:336",
      "src/protocol/pair/ResupplyPairCore.sol:944",
      "src/protocol/pair/ResupplyPairCore.sol:946"
    ],
    "claim": "When a redemption triggers share refactoring, the pair divides `totalBorrow.shares` by `SHARE_REFACTOR_PRECISION` once, but each borrower's `_userBorrowShares` is only divided later during `_increaseUserRewardEpoch()` using floor rounding. There is no remainder accounting, so the sum of lazily-updated user shares can fall below the already-refactored global share total, and borrowers with fewer than `SHARE_REFACTOR_PRECISION` pre-refactor shares round all the way to zero.",
    "impact": "The loss per account is bounded and typically small, but it can permanently leak some debt out of user ownership. In edge cases, a dust borrower can become debt-free after a refactor while the corresponding amount remains embedded in global debt accounting, creating small accounting drift and redistributing residual debt away from rounded-down users.",
    "paths": [
      "Repeated redemptions reduce `totalBorrow.amount` until `totalBorrow.amount * SHARE_REFACTOR_PRECISION < totalBorrow.shares`, triggering `_increaseRewardEpoch()` and a one-time division of global borrow shares.",
      "Borrowers are migrated to the new epoch lazily, and each `_userBorrowShares` value is independently divided by `SHARE_REFACTOR_PRECISION` with floor rounding.",
      "After enough borrowers sync, the sum of user-owned shares can be smaller than `totalBorrow.shares`; very small positions can round to zero shares entirely and stop owing their residual debt."
    ],
    "round": 3,
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
    "id": "F-010",
    "severity": "High",
    "confidence": "high",
    "title": "Excess redemption write-offs are silently discarded, letting users borrow and withdraw against collateral that no longer exists",
    "locations": [
      "src/protocol/pair/ResupplyPairCore.sol:604",
      "src/protocol/pair/ResupplyPairCore.sol:610",
      "src/protocol/pair/ResupplyPairCore.sol:279",
      "src/protocol/pair/ResupplyPairCore.sol:965"
    ],
    "claim": "Redemptions socialize collateral losses by minting `redemptionWriteOff` rewards, but `_syncUserRedemptions` caps each account's loss at zero collateral and discards any excess write-off. The missing loss is never redistributed or booked as bad debt, and `_isSolvent` later trusts the inflated raw `_userCollateralBalance`, so accounts can remain 'solvent' on paper even after the pair's real collateral has already been redeemed away.",
    "impact": "After a large redemption during a stressed market, the pair can become materially undercollateralized while healthy borrowers still appear safely collateralized. Those borrowers can then remove real collateral or open more debt against phantom backing, draining the remaining pool and deepening insolvency.",
    "paths": [
      "A high-LTV borrower and a low-LTV borrower are both outstanding when collateral price falls.",
      "A redemption removes collateral from the pair and mints write-off rewards pro rata to borrow shares.",
      "The high-LTV account's assigned write-off exceeds its collateral, so `_syncUserRedemptions` floors that account at zero and drops the excess loss.",
      "The low-LTV account keeps an overstated `_userCollateralBalance`, passes `_isSolvent`, and can withdraw or borrow against collateral that was already redeemed."
    ]
  },
  {
    "id": "F-011",
    "severity": "Medium",
    "confidence": "low",
    "title": "The pair releases collateral and clears debt before verifying that redemption or liquidation payment was actually settled",
    "locations": [
      "src/protocol/pair/ResupplyPairCore.sol:913",
      "src/protocol/pair/ResupplyPairCore.sol:940",
      "src/protocol/pair/ResupplyPairCore.sol:961",
      "src/protocol/pair/ResupplyPairCore.sol:1037",
      "src/protocol/pair/ResupplyPairCore.sol:1048",
      "src/protocol/pair/ResupplyPairCore.sol:1051"
    ],
    "claim": "Both `redeemCollateral` and `liquidate` trust external handler contracts to supply or burn the debt tokens after the pair has already reduced `totalBorrow` and/or transferred collateral. The pair never verifies in-contract that `_amount` was burned for redemptions or that liquidation debt was actually settled.",
    "impact": "Any bug, misconfiguration, or unexpected callable path in the redemption or liquidation handler escalates into a pair-level loss event: collateral can be released and borrower debt can be erased without a matching debt-token burn. The pair has no defense-in-depth check to stop a bad handler from turning into free collateral extraction.",
    "paths": [
      "A faulty or compromised `redemptionHandler` calls `redeemCollateral` with an arbitrary `_amount` and `_receiver` without first destroying the same amount of debt tokens.",
      "The pair reduces `totalBorrow`, transfers collateral, and only relies on the handler's off-contract logic to have made the system whole.",
      "A faulty or compromised `liquidationHandler` calls `liquidate`; the pair zeroes borrower debt and transfers collateral before `processLiquidationDebt` is asked to burn the offsetting debt."
    ]
  },
  {
    "id": "F-012",
    "severity": "Low",
    "confidence": "medium",
    "title": "Setting `minimumLeftoverDebt` to zero can leave stale borrow shares alive after a full redemption",
    "locations": [
      "src/protocol/ResupplyPair.sol:289",
      "src/protocol/pair/ResupplyPairCore.sol:936",
      "src/protocol/pair/ResupplyPairCore.sol:944",
      "src/protocol/pair/ResupplyPairCore.sol:649",
      "src/protocol/pair/ResupplyPairCore.sol:652",
      "src/protocol/pair/ResupplyPairCore.sol:655"
    ],
    "claim": "Governance can set `minimumLeftoverDebt` to zero, which allows redemptions to drive `totalBorrow.amount` all the way to zero while the one-shot share refactor still leaves nonzero `totalBorrow.shares`. Future borrows then mint fresh shares on top of those leftovers because `toShares` special-cases `total.amount == 0` and never clears the stale share supply.",
    "impact": "This corrupts later debt accounting by carrying old or unowned shares into the next borrow cycle. Debt can be misallocated, some borrow capacity can leak to stale shares, and future repayments/solvency checks can become inconsistent with the intended post-redemption reset state.",
    "paths": [
      "Governance sets `minimumLeftoverDebt` to `0`.",
      "A redemption fully zeros `totalBorrow.amount` but only divides `totalBorrow.shares` once.",
      "A later borrower opens a new position while stale shares are still present, so the new debt is created on top of leftover share supply instead of a clean slate."
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
