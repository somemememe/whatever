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
  },
  {
    "id": "F-009",
    "severity": "High",
    "confidence": "high",
    "title": "Privileged owner can force debt onto users and withdraw the backing MIM",
    "locations": [
      "cauldrons/PrivilegedCauldronV4.sol:15",
      "cauldrons/CauldronV4.sol:654"
    ],
    "claim": "`PrivilegedCauldronV4.addBorrowPosition()` increases `totalBorrow` and a chosen user's `userBorrowPart` without transferring any MIM to that user, while `reduceSupply()` lets the same master owner withdraw the still-idle MIM balance from the cauldron. The owner can therefore convert a victim's remaining collateral headroom into owner-withdrawable MIM or later-liquidatable debt.",
    "impact": "A privileged operator can saddle users with debt they never received, extract the corresponding MIM liquidity to themselves, and/or push victims into liquidation. This is a direct theft/backdoor vector, not merely a bookkeeping inconsistency.",
    "paths": [
      "The master owner calls `addBorrowPosition(victim, amount)` up to the victim's solvency limit.",
      "Because `addBorrowPosition()` does not transfer MIM out, the cauldron still holds the same BentoBox MIM balance.",
      "The owner then calls `reduceSupply(amount)` to withdraw that idle MIM to themselves, leaving the victim with debt but no proceeds.",
      "Alternatively, the owner can wait for price movement or interest accrual and liquidate the victim against the fabricated debt."
    ],
    "round": 3,
    "source_agents": [
      "codex"
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
    "impact": "Freshly assigned debt can be inflated immediately by past interest, unexpectedly overcharging users and potentially making them insolvent or liquidatable. Any migration or administrative flow that uses `addBorrowPosition()` can therefore mint more debt than intended.",
    "paths": [
      "Let time pass without calling `accrue()`.",
      "The master owner calls `addBorrowPosition(user, amount)`.",
      "The next `accrue()` charges elapsed-time interest on both the pre-existing debt and the newly inserted amount."
    ],
    "round": 3,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-011",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Public skim buckets let anyone steal non-atomic staged collateral or MIM",
    "locations": [
      "cauldrons/CauldronV4.sol:252",
      "cauldrons/CauldronV4.sol:270",
      "cauldrons/CauldronV4.sol:344"
    ],
    "claim": "The skim paths do not pull assets from a caller-scoped pending balance. `addCollateral(..., skim=true)` credits any excess collateral shares already sitting on the cauldron's BentoBox balance, and `_repay(..., skim=true)` pulls MIM from BentoBox's own shared holding bucket via `address(bentoBox)`. Any assets pre-positioned into those public buckets for a later second-step transaction can therefore be consumed by whichever caller gets there first.",
    "impact": "Users or integrators that split a skim-based workflow across multiple transactions can lose staged collateral or MIM to front-runners, who can mint themselves collateral credit or repay their own debt with the victim's shares.",
    "paths": [
      "A user transfers collateral shares to the cauldron address in BentoBox and plans to call `addCollateral(..., true, share)` later; an attacker front-runs with `addCollateral(attacker, true, share)` and captures the staged collateral.",
      "An integrator deposits MIM shares to BentoBox's shared holding bucket for a later `repay(..., true, part)`; an attacker calls `repay(attacker, true, part)` first and consumes that shared MIM balance to pay down their own debt."
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
    "id": "F-012",
    "severity": "High",
    "confidence": "high",
    "title": "Unbounded collateralization-rate updates can turn the market into free-borrow or mass-liquidation mode",
    "locations": [
      "cauldrons/CauldronV4.sol:204",
      "cauldrons/CauldronV4.sol:705"
    ],
    "claim": "`setCollateralizationRate()` accepts any value, and `_isSolvent()` directly multiplies collateral by that raw `COLLATERIZATION_RATE`. Setting it above the precision denominator makes positions appear safer than their collateral value supports, while setting it near zero makes even healthy accounts look insolvent.",
    "impact": "A single mistaken or compromised owner update can immediately create an externally exploitable state: borrowers can drain all idle MIM while still passing solvency checks, or liquidators can seize collateral from otherwise healthy users.",
    "paths": [
      "Owner sets `COLLATERIZATION_RATE` above `1e5` -> attacker deposits modest collateral -> attacker borrows up to all available MIM because `_isSolvent()` overcredits collateral value.",
      "Owner sets `COLLATERIZATION_RATE` to `0` or an extremely low value -> any account with debt fails `_isSolvent()` -> third parties liquidate healthy borrowers."
    ]
  },
  {
    "id": "F-013",
    "severity": "High",
    "confidence": "high",
    "title": "Missing interest-rate cap lets a single update brick `accrue()` and freeze core operations",
    "locations": [
      "cauldrons/CauldronV4.sol:104",
      "cauldrons/CauldronV4.sol:180",
      "cauldrons/CauldronV4.sol:662"
    ],
    "claim": "`changeInterestRate()` imposes no sanity bound even though `ONE_PERCENT_RATE` is defined. An extreme `INTEREST_PER_SECOND` can make `extraAmount` exceed `uint128` during `accrue()`, or can explode debt so fast that normal users become instantly insolvent.",
    "impact": "Once `accrue()` starts reverting, every accrue-gated path such as `borrow()`, `repay()`, `removeCollateral()`, `liquidate()`, and `withdrawFees()` becomes unusable, trapping positions and freezing the market. Even non-overflowing but extreme rates can force sudden mass liquidations.",
    "paths": [
      "Owner sets a huge `INTEREST_PER_SECOND` -> next `accrue()` overflows at `.to128()` -> all functions that call `accrue()` revert.",
      "Owner sets a confiscatory but non-overflowing rate -> debt jumps sharply before borrowers can react -> outsiders liquidate them."
    ]
  },
  {
    "id": "F-014",
    "severity": "Medium",
    "confidence": "medium",
    "title": "`reduceSupply()` can withdraw MIM that `withdrawFees()` still counts as earned protocol fees",
    "locations": [
      "cauldrons/CauldronV4.sol:633",
      "cauldrons/CauldronV4.sol:654"
    ],
    "claim": "`reduceSupply()` computes its withdrawable amount from the cauldron's full BentoBox MIM balance and never subtracts `accrueInfo.feesEarned`, even though `withdrawFees()` later assumes those earned fees are still backed by shares held by the cauldron.",
    "impact": "The master owner can confiscate already-accrued protocol revenue or make fee withdrawals revert until enough fresh repayments refill the cauldron balance. If `feeTo` is a treasury distinct from the owner, this is direct revenue theft.",
    "paths": [
      "Interest accrues -> `feesEarned` grows -> owner calls `reduceSupply()` for the full idle MIM balance -> `withdrawFees()` later tries to transfer shares that are no longer there."
    ]
  },
  {
    "id": "F-015",
    "severity": "Medium",
    "confidence": "low",
    "title": "Public `init()` allows hostile first-initialization of any orphaned clone",
    "locations": [
      "cauldrons/CauldronV4.sol:146",
      "cauldrons/CauldronV4.sol:148",
      "cauldrons/CauldronV4.sol:152"
    ],
    "claim": "Clone initialization is permissionless: `init()` is `public`, only checks that `address(collateral) == address(0)`, and does not require the caller to be BentoBox or the master owner. The first caller permanently chooses collateral, oracle, and core risk parameters.",
    "impact": "Any deployment flow that leaves a clone uninitialized, even briefly, can be front-run and permanently poisoned with attacker-chosen configuration. Users interacting with that clone would face malicious pricing, unsafe parameters, and an irreversible setup.",
    "paths": [
      "A clone exists with `collateral == 0` -> attacker calls `init()` first with malicious oracle data and parameters -> legitimate deployer cannot reinitialize it."
    ]
  },
  {
    "id": "F-016",
    "severity": "Low",
    "confidence": "medium",
    "title": "Batch liquidation rounds down each account's debt separately and can strand residual bad debt",
    "locations": [
      "cauldrons/CauldronV4.sol:583",
      "cauldrons/CauldronV4.sol:607",
      "cauldrons/CauldronV4.sol:608"
    ],
    "claim": "`liquidate()` computes `borrowAmount = totalBorrow.toElastic(borrowPart, false)` per user, sums those rounded-down values, and then subtracts the full summed `borrowPart` from `totalBorrow.base`. The floor rounding is applied account-by-account instead of once on the aggregate.",
    "impact": "When many tiny positions are liquidated together, the protocol can under-collect debt by up to roughly one smallest MIM unit per account. That dust is then stranded as residual `elastic` or socialized onto remaining borrowers.",
    "paths": [
      "Attacker splits debt across many dust accounts -> positions become liquidatable -> batch liquidation floors each account's `borrowAmount` independently -> total removed `elastic` is lower than the debt represented by the removed `base`."
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
