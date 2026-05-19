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
    "severity": "Critical",
    "confidence": "high",
    "title": "Anyone can front-run initialization and permanently seize an uninitialized pool",
    "locations": [
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:160",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:175",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:411"
    ],
    "claim": "`init()` is a one-time external initializer with no access control. On any freshly deployed pool, any address can call it first, choose arbitrary `token0`, `token1`, `interestRateAddress`, `ltv/lb/rf`, and overwrite `core` with an attacker-controlled address. Because privileged functions are gated only by `onlyCore`, the attacker permanently becomes the pool controller.",
    "impact": "If deployment and initialization are not atomic, a front-runner can seize the pool before the intended deployer initializes it. Once in control, the attacker can route all `onlyCore` operations through an attacker-controlled core, use malicious oracle responses, and directly transfer out any assets later sent to the pool via privileged flows such as `processFlashLoan`, leading to theft or permanent pool bricking.",
    "paths": [
      "A pool is deployed but remains uninitialized for at least one transaction.",
      "An attacker calls `init()` first and sets `core` to an attacker-controlled address or contract.",
      "The legitimate initializer is locked out by `initialized = true`.",
      "Any funds later routed into the pool can be drained or the market can be permanently misconfigured via the attacker-controlled `onlyCore` entrypoints."
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "Collateral withdrawals pass health checks because redemption validates before the asset transfer leaves the pool",
    "locations": [
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:281",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:302",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:568",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:571",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:591",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:594",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:620",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:623",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:643",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:646"
    ],
    "claim": "`redeem()` and `redeemUnderlying()` burn a user's lend shares and then immediately run `checkHealthFactorLtv*()` before transferring the redeemed tokens out of the pool. However, `userBalanceOftoken0/1()` prices lend balances from `IERC20(token).balanceOf(address(this)) + totalBorrow`, so the not-yet-transferred collateral is still counted during the health-factor check even though the user's share denominator has already been reduced. This lets the check observe an inflated post-withdraw collateral value.",
    "impact": "A borrower can withdraw collateral that is backing an opposite-side loan while still passing the LTV check, then receive the tokens moments later. After the transfer completes, the position can become undercollateralized or outright insolvent, leaving bad debt for lenders.",
    "paths": [
      "A user deposits collateral on one side and borrows the opposite asset.",
      "The user calls `redeem()` or `redeemUnderlying()` to withdraw the collateral side.",
      "The pool burns lend shares and checks health factor while the soon-to-be-withdrawn tokens are still in the contract balance used for collateral valuation.",
      "The check passes, the transfer executes, and the position is left with less real collateral than the validation assumed."
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "New LPs can steal previously accrued borrower interest because `lend()` mints shares against stale debt",
    "locations": [
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:388",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:511",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:518",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:533"
    ],
    "claim": "`lend()` never calls `accrueInterest()`. It mints lend shares using `tokenBalance + totalBorrow`, but `totalBorrow` can be stale for many blocks while interest has already economically accrued. Deposits made during that window are therefore priced against an understated pool value and receive too many lend shares.",
    "impact": "A late depositor can wait for a large amount of interest to accrue, deposit just before any accrual-triggering action, and receive an outsized ownership share. Once interest is accrued by a later state-changing call, the attacker can redeem and capture value that should have belonged to prior lenders.",
    "paths": [
      "Borrows remain open while `lastUpdated` lags and interest accumulates off-chain/economically but is not yet added to `totalBorrow`.",
      "An attacker deposits via `lend()` and receives shares priced from stale `totalBorrow`.",
      "Any later call such as `borrow`, `redeem`, `repay`, `liquidate`, or `processFlashLoan` runs `accrueInterest()`.",
      "The attacker redeems the over-minted shares and extracts previously accrued interest from existing LPs."
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
    "title": "Liquidation uses `100 - lb` instead of the borrow limit, creating a large undercollateralized but non-liquidatable zone",
    "locations": [
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:234",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:243",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:257",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:266",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:779",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:781",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:832",
      "0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:833"
    ],
    "claim": "Borrow safety checks use `ltv`, but liquidation eligibility uses `(100 - lb)` instead. When `ltv` is materially lower than `100 - lb`—for example 80% LTV with a 5% liquidation bonus—positions can exceed the protocol's stated borrow limit and still remain non-liquidatable until they deteriorate much further.",
    "impact": "The protocol can accumulate a wide band of unhealthy positions that are above the allowed borrow limit but cannot yet be liquidated. Continued price movement or interest accrual inside that gap makes lender losses more likely and can convert recoverable positions into bad debt.",
    "paths": [
      "A user borrows up to the configured `ltv` cap.",
      "Collateral value falls or debt grows so the position moves above `ltv` but remains below the looser `(100 - lb)` liquidation threshold.",
      "Liquidators cannot act during that unhealthy interval.",
      "Further deterioration pushes the account closer to insolvency before liquidation becomes possible, increasing realized losses for LPs."
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
    "id": "F-005",
    "severity": "Critical",
    "confidence": "high",
    "title": "Borrowing rounds debt shares down, letting new borrowers take more underlying than the liability they receive",
    "locations": [
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:44",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:48",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:664",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:685"
    ],
    "claim": "`borrow()` mints borrow shares with floor division via `calculateShare`, but debt shares should round up when a user receives underlying. Once accrued interest makes `totalBorrow / totalBorrowShare > 1`, a borrower can borrow an amount whose exact share cost is fractional and receive fewer debt shares than the borrowed value requires.",
    "impact": "The borrower extracts excess tokens while part of the liability is socialized onto the existing borrow-share base, creating bad debt and enabling pool insolvency.",
    "paths": [
      "Wait until accrued interest increases `totalBorrow` above `totalBorrowShare` for an asset.",
      "Call `borrow()` with an amount whose exact share conversion is just above an integer boundary.",
      "Because `calculateShare` floors, the position receives too few borrow shares while the pool still transfers the full underlying amount."
    ]
  },
  {
    "id": "F-006",
    "severity": "Critical",
    "confidence": "high",
    "title": "Exact-underlying redemptions burn LP shares with floor rounding, allowing lenders to withdraw more assets than their shares cover",
    "locations": [
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:56",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:57",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:614",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:637"
    ],
    "claim": "`redeemUnderlying()` converts a requested underlying amount into LP shares with `getShareByValue`, which floors instead of rounding up. When one LP share is worth more than one unit of the asset, a redeemer can request an amount that should cost `n + ε` shares but only burns `n` shares.",
    "impact": "An LP can repeatedly over-withdraw underlying and drain value from the remaining lenders. This does not depend on bypassing the health-factor check; it is a direct accounting flaw in the share burn calculation.",
    "paths": [
      "Let lender share price rise above 1 through normal borrower interest accrual.",
      "Call `redeemUnderlying()` for an amount slightly below the value of the next whole share threshold.",
      "The pool transfers the full underlying amount but burns too few LP shares."
    ]
  },
  {
    "id": "F-007",
    "severity": "High",
    "confidence": "high",
    "title": "Liquidation seizes collateral by value but burns too few collateral shares from the victim",
    "locations": [
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:56",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:57",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:805",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:806",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:857",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:858"
    ],
    "claim": "After computing the collateral amount to seize, `liquidateInternal()` converts that value into LP shares with `getShareByValue`, which floors. A liquidator can therefore receive collateral worth more than the number of shares removed from the unhealthy position.",
    "impact": "Liquidations can over-seize collateral and push the shortfall onto the remaining LP share base. A liquidator or colluding account can extract extra value whenever collateral share price exceeds 1.",
    "paths": [
      "Target an unhealthy position whose collateral share price is above 1.",
      "Liquidate an amount whose seized-collateral conversion has a fractional LP-share component.",
      "The pool transfers or reassigns the full collateral value while burning only the floored number of victim LP shares."
    ]
  },
  {
    "id": "F-008",
    "severity": "Critical",
    "confidence": "high",
    "title": "Batch liquidation collapses two-token settlements into one signed integer, allowing opposite-side liquidations to cancel out",
    "locations": [
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:813",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:814",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:866",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:867",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:899",
      "onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol:923"
    ],
    "claim": "`liquidateMulti()` aggregates all per-position settlements into a single signed `liquidatedAmountTotal` and a single signed `recAmountINtotal`. Because negative values mean token0 and positive values mean token1, batching liquidations across both debt directions loses the two-dimensional token accounting and permits cross-token netting.",
    "impact": "A caller can combine token0-debt and token1-debt liquidations so that the signed totals partially or fully cancel, while the internal liquidation logic still reduces debts and seizes collateral for every position. This can produce free or underpaid liquidations and direct theft of user collateral.",
    "paths": [
      "Include at least one `amount < 0` liquidation and one `amount > 0` liquidation in the same `liquidateMulti()` call.",
      "Their token0/token1 payment obligations are netted into a single scalar instead of being tracked separately.",
      "The batch updates both positions, but the final settlement can be zero or materially smaller than the true two-token amount owed."
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
