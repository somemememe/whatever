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
  }
]

## This Round's Agent Outputs
### Agent: codex
```
[
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "Unconditional reward claiming can globally freeze borrowing, withdrawals, repayments, and liquidations",
    "locations": [
      "src/protocol/RewardDistributorMultiEpoch.sol:224",
      "src/protocol/pair/ResupplyPairCore.sol:321",
      "src/protocol/pair/ResupplyPairCore.sol:599",
      "src/protocol/pair/ResupplyPairCore.sol:833"
    ],
    "claim": "Every checkpoint unconditionally calls `IResupplyRegistry(registry).claimRewards(address(this))`. Because checkpoints are embedded in solvency syncing and repayment paths, any revert in the external reward-claim pipeline bricks core pair operations even though reward collection is ancillary.",
    "impact": "A failing reward source, claimer, or downstream reward contract can lock user debt management and risk controls: borrowers can be unable to borrow, remove collateral, repay-with-collateral, or be liquidated, allowing bad debt and user lockups to accumulate.",
    "paths": [
      "borrow/removeCollateral/leveragedPosition -> `isSolvent` -> `_syncUserRedemptions` -> `_checkpoint` -> `_fetchIncentives` -> external `claimRewards` revert",
      "repay/repayWithCollateral -> `_repay` or `_syncUserRedemptions` -> `_checkpoint` -> `_fetchIncentives` -> external `claimRewards` revert",
      "liquidate -> `_isSolventSync` -> `_syncUserRedemptions` -> `_checkpoint` -> `_fetchIncentives` -> external `claimRewards` revert"
    ]
  },
  {
    "id": "F-006",
    "severity": "High",
    "confidence": "medium",
    "title": "Interest accrual silently forgives entire periods once `uint128` debt headroom is exhausted",
    "locations": [
      "src/protocol/pair/ResupplyPairCore.sol:481",
      "src/protocol/pair/ResupplyPairCore.sol:485",
      "src/protocol/pair/ResupplyPairCore.sol:492",
      "src/protocol/pair/ResupplyPairCore.sol:531"
    ],
    "claim": "If accrued interest would make `totalBorrow.amount` exceed `type(uint128).max`, `_calculateInterest` zeroes `interestEarned` instead of capping or reverting, and `_addInterest` still advances `lastTimestamp`. The skipped interval's interest is therefore permanently lost.",
    "impact": "Large borrowers can avoid paying potentially massive accrued interest once utilization and elapsed time are high enough, materially undercharging the protocol and distorting solvency, fee accrual, and liquidation math.",
    "paths": [
      "Set or reach a very large `borrowLimit`/`totalBorrow.amount` close to `uint128` max",
      "Wait long enough, or let the rate calculator return a high rate, so `interestEarned + totalBorrow.amount > type(uint128).max`",
      "Any later call that runs `_addInterest` permanently discards that interval's interest and moves `lastTimestamp` forward"
    ]
  },
  {
    "id": "F-007",
    "severity": "High",
    "confidence": "high",
    "title": "Zero oracle prices cause division-by-zero reverts across critical pair flows",
    "locations": [
      "src/protocol/pair/ResupplyPairCore.sol:573",
      "src/protocol/pair/ResupplyPairCore.sol:688",
      "src/protocol/pair/ResupplyPairCore.sol:955",
      "src/protocol/pair/ResupplyPairCore.sol:1001"
    ],
    "claim": "`_updateExchangeRate` computes `1e36 / oraclePrice` without validating that `oraclePrice` is non-zero. A zero response from the configured oracle hard-reverts all callers.",
    "impact": "If the oracle ever returns zero, borrowing, leveraged positions, redemptions, liquidations, and collateral withdrawals for active borrowers all fail. This can trap positions and block liquidation exactly when the price feed is already unhealthy.",
    "paths": [
      "`IOracle.getPrices(address(collateral)) == 0`",
      "`borrow`, `leveragedPosition`, `repayWithCollateral`, `liquidate`, or `redeemCollateral` calls `_updateExchangeRate` and reverts",
      "`removeCollateral*` also reverts for borrowers that still have debt because it refreshes the exchange rate before checking solvency"
    ]
  },
  {
    "id": "F-008",
    "severity": "High",
    "confidence": "medium",
    "title": "Redemption and liquidation trust external handlers to burn debt but never verify it on-chain",
    "locations": [
      "src/protocol/pair/ResupplyPairCore.sol:913",
      "src/protocol/pair/ResupplyPairCore.sol:940",
      "src/protocol/pair/ResupplyPairCore.sol:959",
      "src/protocol/pair/ResupplyPairCore.sol:993",
      "src/protocol/pair/ResupplyPairCore.sol:1038",
      "src/protocol/pair/ResupplyPairCore.sol:1050"
    ],
    "claim": "`redeemCollateral` and `liquidate` mutate debt accounting and release collateral based only on trusted handler calls; the pair itself never checks that the corresponding debt tokens were actually transferred in or burned. A buggy or compromised handler can therefore forgive debt or extract collateral for free.",
    "impact": "Any failure in the privileged redemption/liquidation module directly creates unbacked debt or drains pair collateral, and the pair has no invariant check to stop it.",
    "paths": [
      "Compromised or buggy `redemptionHandler` calls `redeemCollateral` with arbitrary `_amount`/`_receiver`; pair reduces `totalBorrow.amount` and transfers collateral without validating a burn",
      "Compromised or buggy `liquidationHandler` calls `liquidate`; pair clears borrower shares and transfers collateral before/without proving that stable debt was burned"
    ]
  },
  {
    "id": "F-009",
    "severity": "Low",
    "confidence": "low",
    "title": "Share-refactor floor rounding leaks small amounts of debt during epoch migration",
    "locations": [
      "src/protocol/pair/ResupplyPairCore.sol:336",
      "src/protocol/pair/ResupplyPairCore.sol:944",
      "src/protocol/pair/ResupplyPairCore.sol:946"
    ],
    "claim": "When redemptions trigger a share refactor, `totalBorrow.shares` is divided once while each user's shares are lazily divided with floor rounding during `_increaseUserRewardEpoch`. The per-user floor loss is not reconciled, so some debt becomes unowned and small borrowers can round fully to zero shares.",
    "impact": "This creates permanent accounting leakage and slightly understates borrower debt after refactors. The loss per account is small, but it accumulates across many borrowers and epochs and makes the global share supply diverge from the sum of user liabilities.",
    "paths": [
      "Repeated redemptions drive `totalBorrow.amount * SHARE_REFACTOR_PRECISION < totalBorrow.shares`",
      "`_increaseRewardEpoch` divides global shares",
      "Borrowers later checkpoint and each individual `_userBorrowShares` value is floor-divided independently, dropping residual debt shares"
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
