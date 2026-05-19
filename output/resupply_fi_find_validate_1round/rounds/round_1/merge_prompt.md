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
    "confidence": "medium",
    "title": "Redemption write-off shortfalls are silently discarded on undercollateralized borrowers",
    "locations": [
      "0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/RewardDistributorMultiEpoch.sol:162",
      "0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/RewardDistributorMultiEpoch.sol:225",
      "0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:599",
      "0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:604",
      "0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:610",
      "0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:906",
      "0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:965"
    ],
    "claim": "`redeemCollateral()` removes real collateral from the pair immediately and only mints non-claimable `redemptionWriteOff` rewards to socialize that loss later. When a borrower is eventually synced, `_syncUserRedemptions()` converts their accrued write-off into a collateral deduction but caps the result at zero. If a borrower has less remaining collateral than the write-off allocated to their borrow shares, the uncovered portion is simply erased instead of being preserved as bad debt or charged elsewhere.",
    "impact": "After a redemption against a pool that already contains undercollateralized borrowers, aggregate user collateral accounting can stay above the pair's real collateral balance. That accounting hole lets earlier withdrawers/liquidations consume collateral that should have absorbed the missing write-off, pushing losses onto later users or protocol insurance and creating hidden insolvency.",
    "paths": [
      "A borrower becomes undercollateralized before liquidation, so their `_userCollateralBalance` is already smaller than the collateral haircut implied by their debt share.",
      "A redemption executes and transfers collateral out of the pair, then mints `redemptionWriteOff` instead of debiting each borrower inline.",
      "When the undercollateralized borrower is later checkpointed, `_calcRewardIntegral()` allocates write-off rewards by borrow shares and `_syncUserRedemptions()` computes `rTokens`.",
      "If `rTokens` exceeds that account's remaining collateral, `_userCollateralBalance` is floored to zero and the excess write-off disappears.",
      "The pair's summed user collateral balances now exceed actual collateral by the discarded amount, enabling over-withdrawal until the shortfall surfaces as protocol bad debt."
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "low",
    "title": "Oracle prices are inverted without decimal normalization or zero checks",
    "locations": [
      "0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/ResupplyPair.sol:176",
      "0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:163",
      "0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:573"
    ],
    "claim": "The pair stores an arbitrary oracle address and `_updateExchangeRate()` blindly computes `1e36 / getPrices(collateral)` without consulting `IOracle.decimals()` or checking that the returned price is non-zero. Any oracle that reports prices in a non-18-decimal scale, or transiently returns zero, will produce a materially wrong exchange rate or revert the update entirely.",
    "impact": "A mis-scaled oracle can make positions appear much safer or riskier than they are, leading to overborrowing, wrongful liquidations, or redemptions at the wrong collateral price. A zero price return causes `_updateExchangeRate()` to revert, which can freeze borrow, liquidation, redemption, leveraged-position, and collateral-removal flows that refresh the exchange rate.",
    "paths": [
      "The pair is deployed with, or later switched to, an oracle whose `getPrices()` output is not already 1e18-scaled or can return zero.",
      "A state-changing path calls `_updateExchangeRate()`, which inverts the raw oracle output as `1e36 / price`.",
      "If the price scale is wrong, solvency and redemption math use a corrupted exchange rate; if the price is zero, the call reverts and blocks the affected operation."
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
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "Convex pool migration can hide live collateral and freeze withdrawals/redemptions",
    "locations": [
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/ResupplyPair.sol:382",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/ResupplyPair.sol:399",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/ResupplyPair.sol:406",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/ResupplyPair.sol:421"
    ],
    "claim": "Convex migration only moves `stakedBalance` from the old rewards contract, but staking mode/accounting are keyed off `convexPid != 0`. If collateral is sitting locally when the pid changes, that balance is never migrated yet `totalCollateral()` starts reading only the staked balance, so core accounting and unstake paths look in the wrong place.",
    "impact": "A normal pool activation/migration can make all existing collateral disappear from pair accounting, causing withdrawals, redemptions, and liquidations to revert while borrowers still appear to have recorded collateral. Funds remain stranded until privileged recovery, and solvency checks drift from real collateral.",
    "paths": [
      "Users deposit while `convexPid == 0` so collateral remains on the pair contract.",
      "Owner later calls `setConvexPool(validPid)`.",
      "`_updateConvexPool` deposits only `stakedBalance` (often 0), leaves local collateral untouched, and then sets `convexPid = validPid`.",
      "From then on `totalCollateral()` and `_unstakeUnderlying()` read the staking contract instead of the pair's local balance, breaking removals/redemptions/liquidations."
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "The write-off token can be invalidated like a normal reward, disabling redemption loss accounting",
    "locations": [
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:177",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/RewardDistributorMultiEpoch.sol:125",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/RewardDistributorMultiEpoch.sol:129",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:599",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:965"
    ],
    "claim": "The internal `redemptionWriteOff` token is inserted into the generic reward list and can be invalidated by `invalidateReward`. Once invalidated, redemptions still mint write-off tokens, but `_calcRewardIntegral` skips the token entirely, so `_syncUserRedemptions` stops reducing borrower collateral for socialized losses.",
    "impact": "Collateral can be redeemed out of the pair while recorded borrower collateral stays artificially high, leading to false solvency, bad liquidations, and insolvency. If the token is later revived, missed write-offs are redistributed against the wrong, current share set, letting prior borrowers escape losses.",
    "paths": [
      "Reward manager calls `invalidateReward(address(redemptionWriteOff))`.",
      "The redemption handler continues calling `redeemCollateral`, which still mints write-off supply.",
      "Borrowers interact normally, but `_syncUserRedemptions` no longer deducts their share of redeemed collateral.",
      "If the token is revived later, the accumulated supply is allocated to current borrowers instead of the borrowers who actually bore the redeemed debt."
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "high",
    "title": "Any reverting reward hook or reward token can brick core lending operations",
    "locations": [
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/RewardDistributorMultiEpoch.sol:158",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/RewardDistributorMultiEpoch.sol:185",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/RewardDistributorMultiEpoch.sol:224",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/RewardDistributorMultiEpoch.sol:226",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/RewardDistributorMultiEpoch.sol:247",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:299",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:841"
    ],
    "claim": "Every borrower sync/checkpoint unconditionally calls the external reward claimer and then touches every registered reward token via `balanceOf` and, during claims, `safeTransfer`. There is no isolation layer, so a single reverting reward hook or malformed reward token makes `_checkpoint` revert everywhere it is used.",
    "impact": "Borrowing, collateral removal, repayment, liquidation sync, and reward claims can all fail pair-wide until governance intervenes. Because the pair auto-registers external reward assets such as the gov token/CRV/CVX, this is a real availability dependency rather than a purely theoretical edge case.",
    "paths": [
      "A registered reward token starts reverting on `balanceOf` or `transfer`, or the registry reward claimer reverts.",
      "Any call path that reaches `_checkpoint` or `_syncUserRedemptions` reverts.",
      "Core actions such as `borrow`, `removeCollateral`, `repay`, `liquidate`, `leveragedPosition`, and `repayWithCollateral` become unavailable."
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "low",
    "title": "Interest overflow silently forgives an entire accrual period",
    "locations": [
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:481",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:485",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:492",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:533",
      "onchain_auto/0x6e90c85a495d54c6d7e1f3400fef1f6e59f86bd6/src/protocol/pair/ResupplyPairCore.sol:537"
    ],
    "claim": "If accrued interest would push `totalBorrow.amount` above `uint128.max`, `_calculateInterest` zeroes `interestEarned` instead of reverting or saturating, but `_addInterest` still advances `lastTimestamp`. The whole elapsed period is therefore skipped with no interest charged.",
    "impact": "At sufficiently large debt or after long inactivity, borrowers can erase a large amount of accrued interest, underpay protocol revenue, and distort total debt accounting. The condition is configuration- and scale-dependent, but the failure mode is silent once reached.",
    "paths": [
      "Debt grows near the `uint128` accounting ceiling or governance sets a very large borrow limit.",
      "No one calls `addInterest` for a long enough interval.",
      "The next accrual lands in the overflow branch, resets `interestEarned` to zero, and updates the timestamp anyway."
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
