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
    "title": "`cook()` solvency enforcement can be cleared by `ACTION_ACCRUE` or any unsupported action",
    "locations": [
      "cauldrons/CauldronV4.sol:369",
      "cauldrons/CauldronV4.sol:456",
      "cauldrons/CauldronV4.sol:488",
      "cauldrons/CauldronV4.sol:527",
      "cauldrons/CauldronV4.sol:538"
    ],
    "claim": "`cook()` sets `status.needsSolvencyCheck = true` after `ACTION_BORROW` and `ACTION_REMOVE_COLLATERAL`, but any unhandled action falls through to `_additionalCookAction()`. In `CauldronV4` that hook has an empty implementation and does not revert, yet `cook()` blindly replaces the current `status` with its return value. Because `ACTION_ACCRUE` is declared but never handled, and arbitrary unsupported action IDs also route there, a user can append one of those actions after borrowing or removing collateral to reset `needsSolvencyCheck` to `false` and skip the final insolvency check entirely.",
    "impact": "An attacker can borrow MIM or withdraw collateral and finish the transaction undercollateralized, creating immediate bad debt and potentially draining the cauldron's available MIM.",
    "paths": [
      "Call `cook()` with `ACTION_BORROW` followed by `ACTION_ACCRUE`; the borrow succeeds, the empty hook returns a zeroed `CookStatus`, and the final solvency check is skipped.",
      "Call `cook()` with `ACTION_REMOVE_COLLATERAL` followed by any unsupported action ID; collateral is removed, `needsSolvencyCheck` is cleared, and the transaction can end insolvent."
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "medium",
    "title": "Cauldron hardcodes 18-decimal oracle precision and ignores `IOracle.decimals()`",
    "locations": [
      "interfaces/IOracle.sol:5",
      "cauldrons/CauldronV4.sol:110",
      "cauldrons/CauldronV4.sol:201",
      "cauldrons/CauldronV4.sol:226",
      "cauldrons/CauldronV4.sol:583"
    ],
    "claim": "The protocol exposes `IOracle.decimals()`, but CauldronV4 never reads or normalizes oracle output and instead assumes every rate is scaled by `EXCHANGE_RATE_PRECISION = 1e18`. If a cauldron is configured with any compatible oracle that reports rates at a different precision, all solvency checks and liquidation seize calculations are distorted by that scale mismatch.",
    "impact": "A mis-scaled oracle can let users borrow far more MIM than intended or cause liquidations to seize materially too little collateral, leaving the protocol with large bad debt.",
    "paths": [
      "Deploy or initialize a cauldron with an oracle whose `get()` rate uses 8 decimals; `_isSolvent()` compares debt against a rate that is off by `1e10`, allowing undercollateralized borrowing.",
      "Liquidations on the same market reuse the same bad scale in `liquidate()`, so even liquidators cannot recover enough collateral to cover the debt."
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-003",
    "severity": "Critical",
    "confidence": "medium",
    "title": "Zero oracle rates are accepted and make any borrower with nonzero collateral appear solvent",
    "locations": [
      "cauldrons/CauldronV4.sol:158",
      "cauldrons/CauldronV4.sol:201",
      "cauldrons/CauldronV4.sol:227",
      "cauldrons/CauldronV4.sol:230",
      "cauldrons/CauldronV4.sol:578"
    ],
    "claim": "Neither `init()` nor `updateExchangeRate()` validates that the oracle returned success or that the returned rate is nonzero before storing or using it. If the cached `exchangeRate` becomes zero, `_isSolvent()` reduces the debt side of the solvency inequality to zero, so any account with positive collateral passes solvency checks, and `liquidate()` also stops treating those borrowers as insolvent.",
    "impact": "During a zero-rate oracle event, users can post dust collateral, borrow out the cauldron's MIM, and remain effectively unliquidatable until a valid price is restored.",
    "paths": [
      "At initialization, `oracle.get()` can return `(false, 0)` or another zero rate and the clone stores `exchangeRate = 0` without reverting.",
      "Later, a user borrows through `borrow()` or `cook(ACTION_BORROW, ...)`; the post-action solvency check uses the zero cached rate, so the position is accepted despite being deeply undercollateralized."
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
    "title": "Oracle failures fall back to an unbounded stale price across borrowing, withdrawals, and liquidations",
    "locations": [
      "cauldrons/CauldronV4.sol:216",
      "cauldrons/CauldronV4.sol:226",
      "cauldrons/CauldronV4.sol:232",
      "cauldrons/CauldronV4.sol:329",
      "cauldrons/CauldronV4.sol:567"
    ],
    "claim": "`updateExchangeRate()` silently reuses the cached `exchangeRate` whenever `oracle.get()` reports `updated == false`, and there is no freshness bound on how old that cached price may be. The same fallback is consumed by the `solvent` modifier used for `borrow()` and `removeCollateral()`, as well as by `liquidate()`, so the market keeps operating indefinitely on stale pricing during oracle outages.",
    "impact": "After a collateral price drop, borrowers can continue borrowing or withdraw collateral against an obsolete favorable price and leave bad debt; conversely, if the stale price is too low, healthy users can be liquidated unfairly.",
    "paths": [
      "The oracle stops updating after a sharp collateral selloff; `borrow()` still succeeds because the `solvent` modifier receives the old cached exchange rate from `updateExchangeRate()`.",
      "During the same outage, `removeCollateral()` and `liquidate()` use that same stale rate, either blocking needed liquidations or liquidating solvent users depending on the stale price direction."
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Permissionless `withdrawFees()` can send accrued fees to an unset `feeTo` address",
    "locations": [
      "cauldrons/CauldronV4.sol:633",
      "cauldrons/CauldronV4.sol:635",
      "cauldrons/CauldronV4.sol:638",
      "cauldrons/CauldronV4.sol:647"
    ],
    "claim": "`withdrawFees()` is callable by anyone and never checks that `masterContract.feeTo()` is nonzero before transferring accrued MIM shares there. Because `feeTo` starts unset until the master owner configures it on the master contract, any caller can force fee withdrawal while the destination is still `address(0)`.",
    "impact": "Accrued protocol fees can be irrecoverably misdirected before fee configuration, destroying revenue and reducing the cauldron's usable MIM liquidity by the amount withdrawn.",
    "paths": [
      "Allow interest or liquidation fees to accrue while the master contract's `feeTo` is still unset, then call `withdrawFees()` on a clone before the owner configures the recipient."
    ],
    "round": 2,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "high",
    "title": "Stranded ETH in the cauldron can be drained through `cook(ACTION_CALL)`",
    "locations": [
      "cauldrons/CauldronV4.sol:402",
      "cauldrons/CauldronV4.sol:427",
      "cauldrons/CauldronV4.sol:446",
      "cauldrons/CauldronV4.sol:465",
      "cauldrons/CauldronV4.sol:510"
    ],
    "claim": "`cook()` is payable, but it never accounts for how much ETH the current caller actually supplied or refunds any excess. `_call()` then forwards an arbitrary `values[i]` amount with a raw `callee.call{value: value}` taken from the contract's entire ETH balance. As a result, any ETH already sitting in the cauldron can be sent out by a later arbitrary caller.",
    "impact": "Any ETH accidentally left in the contract becomes permissionlessly stealable. This includes user overpayments to `cook()`, ETH force-sent via `selfdestruct`, or any integration mistake that leaves native ETH in the cauldron.",
    "paths": [
      "Get ETH into the cauldron, for example by overpaying a prior payable `cook()` call or by force-sending ETH.",
      "Call `cook()` with `ACTION_CALL` targeting an attacker-controlled address and set `values[i]` to the stranded ETH balance; `_call()` forwards that ETH out of the cauldron."
    ],
    "round": 2,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-008",
    "severity": "High",
    "confidence": "low",
    "title": "Checkpoint-token reentrancy before state updates can corrupt privileged liquidation accounting",
    "locations": [
      "cauldrons/CauldronV4.sol:580",
      "cauldrons/CauldronV4.sol:581",
      "cauldrons/CauldronV4.sol:591",
      "cauldrons/CauldronV4.sol:592",
      "cauldrons/CauldronV4.sol:607",
      "cauldrons/PrivilegedCheckpointCauldronV4.sol:23",
      "cauldrons/PrivilegedCheckpointCauldronV4.sol:29"
    ],
    "claim": "`PrivilegedCheckpointCauldronV4` overrides `_beforeUserLiquidated()` to make an external `user_checkpoint()` call on the collateral token before `liquidate()` updates `userBorrowPart`, `userCollateralShare`, and global borrow totals. Because `liquidate()` caches `availableBorrowPart`, `borrowPart`, and `borrowAmount` before that hook and there is no reentrancy guard, a reentrant checkpoint token can liquidate the same user again against stale outer-call state.",
    "impact": "A malicious or compromised checkpoint token can desynchronize per-user debt from `totalBorrow`, over-process liquidation state, or force liquidations to revert, causing bad debt or making insolvent accounts difficult to liquidate.",
    "paths": [
      "Use `PrivilegedCheckpointCauldronV4` with a collateral token whose `user_checkpoint()` reenters `liquidate()` on the same victim during the outer liquidation hook.",
      "Have the reentrant liquidation process a smaller `borrowPart` first, then let the outer call resume with its stale cached `availableBorrowPart` and `borrowAmount`, causing inconsistent user and global accounting."
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
    "id": "F-009",
    "severity": "High",
    "confidence": "high",
    "title": "Privileged owner can force debt onto users and withdraw the backing MIM",
    "locations": [
      "cauldrons/PrivilegedCauldronV4.sol:15",
      "cauldrons/CauldronV4.sol:654"
    ],
    "claim": "`addBorrowPosition()` increases `totalBorrow` and a chosen user's `userBorrowPart` without transferring any MIM to that user, while `reduceSupply()` lets the same privileged owner withdraw the still-idle MIM balance from the cauldron. The owner can therefore turn any user's collateral headroom into owner-withdrawable MIM or later-liquidatable debt.",
    "impact": "A privileged operator can saddle victims with debt they never received, extract the corresponding MIM liquidity to themselves, and/or push the victim into liquidation. This is a direct theft/backdoor vector rather than a mere configuration footgun.",
    "paths": [
      "Owner calls `addBorrowPosition(victim, amount)` up to the victim's solvency limit.",
      "Because no MIM is sent out during `addBorrowPosition`, the cauldron still holds the same BentoBox MIM balance.",
      "Owner calls `reduceSupply(amount)` to withdraw that idle MIM to themselves, leaving the victim owing debt with no proceeds received.",
      "Alternatively, owner waits for interest or price movement and liquidates the victim's collateral against the fabricated debt."
    ]
  },
  {
    "id": "F-010",
    "severity": "Medium",
    "confidence": "high",
    "title": "Privileged debt injections accrue retroactive interest from before the debt existed",
    "locations": [
      "cauldrons/PrivilegedCauldronV4.sol:15",
      "cauldrons/CauldronV4.sol:164"
    ],
    "claim": "`addBorrowPosition()` mutates `totalBorrow` without first calling `accrue()`. On the next `accrue()`, the full elapsed time since `lastAccrued` is applied to the newly added borrow amount as though that debt had existed for the entire interval.",
    "impact": "Freshly assigned debt can be inflated immediately by past interest, unexpectedly overcharging users and potentially making them insolvent or liquidatable. This also corrupts migrations/accounting flows that rely on `addBorrowPosition()` to mirror an existing debt balance.",
    "paths": [
      "Time passes without an `accrue()` call.",
      "Owner calls `addBorrowPosition(user, amount)`.",
      "The next `accrue()` charges elapsed-time interest on both the old debt and the newly inserted amount."
    ]
  },
  {
    "id": "F-011",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Skim mode spends from shared BentoBox holding buckets, so staged shares are stealable",
    "locations": [
      "cauldrons/CauldronV4.sol:252",
      "cauldrons/CauldronV4.sol:270",
      "cauldrons/CauldronV4.sol:344"
    ],
    "claim": "`addCollateral(..., skim=true)` credits any excess collateral shares already sitting on the cauldron's BentoBox balance, and `repay(..., skim=true)` pulls MIM from `address(bentoBox)` instead of a caller-scoped balance. Those skim sources are shared buckets, so assets parked there for a later second-step action can be consumed by any caller who arrives first.",
    "impact": "Users or integrators that pre-stage shares in separate transactions can lose them to front-runners, who can either mint themselves collateral or repay their own debt with the victim's shares. Any residual shares accidentally left on the skim addresses are similarly free for the next caller to capture.",
    "paths": [
      "Victim deposits collateral shares to the cauldron's BentoBox balance and plans to call `addCollateral(..., true, ...)` later.",
      "Attacker front-runs with `addCollateral(attacker, true, share)` and captures the staged collateral.",
      "Victim deposits MIM shares to `address(bentoBox)` for a later `repay(..., true, ...)`.",
      "Attacker calls `repay(attacker, true, part)` and consumes the shared MIM balance to pay down their own debt."
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
