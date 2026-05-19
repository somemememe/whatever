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
  }
]

## This Round's Agent Outputs
### Agent: codex
```
[
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "Anyone can burn accrued fees before `feeTo` is configured",
    "locations": [
      "cauldrons/CauldronV4.sol:633",
      "cauldrons/CauldronV4.sol:635",
      "cauldrons/CauldronV4.sol:638",
      "cauldrons/CauldronV4.sol:647"
    ],
    "claim": "`withdrawFees()` is permissionless and blindly transfers to `masterContract.feeTo()` even when that address is still `address(0)`. Because `feeTo` starts unset until the master owner calls `setFeeTo`, any caller can trigger a transfer of accrued MIM shares to the zero address.",
    "impact": "Protocol fees can be permanently burned, and the burn comes out of the cauldron's live MIM liquidity. That can destroy revenue and also reduce the liquidity available for future borrowing/liquidation flows.",
    "paths": [
      "Let fees accrue while the master contract's `feeTo` is still unset, then call `withdrawFees()` on a clone before the owner configures `feeTo`."
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "high",
    "title": "Any ETH stranded in the cauldron can be stolen with `cook()`",
    "locations": [
      "cauldrons/CauldronV4.sol:402",
      "cauldrons/CauldronV4.sol:411",
      "cauldrons/CauldronV4.sol:427",
      "cauldrons/CauldronV4.sol:446",
      "cauldrons/CauldronV4.sol:465"
    ],
    "claim": "`cook()` never tracks how much of the contract's ETH balance belongs to the current call. `_call()` can forward arbitrary `value`, and that `value` is paid from the cauldron's entire ETH balance rather than only the current `msg.value`.",
    "impact": "Any ETH accidentally left in the contract becomes permissionlessly stealable. This includes overpayments, integration mistakes, forced ETH sent via `selfdestruct`, or ETH left behind by previous users.",
    "paths": [
      "First get ETH into the cauldron (for example by overpaying a prior `cook()` call or force-sending ETH).",
      "Then call `cook()` with an `ACTION_CALL` whose `callee` is an attacker-controlled address and whose `values[i]` equals the stranded ETH balance."
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Batch liquidation can leave unrecoverable ghost debt through per-user rounding",
    "locations": [
      "cauldrons/CauldronV4.sol:583",
      "cauldrons/CauldronV4.sol:607",
      "cauldrons/CauldronV4.sol:608",
      "cauldrons/CauldronV4.sol:174"
    ],
    "claim": "`liquidate()` computes each victim's `borrowAmount` independently with `totalBorrow.toElastic(borrowPart, false)` and then manually subtracts the summed `allBorrowAmount` and `allBorrowPart` from `totalBorrow`. When many small positions are liquidated together, the individual round-downs can sum to less than the elastic amount implied by `allBorrowPart`.",
    "impact": "Liquidators can clear more debt parts than the MIM they actually repay, pushing the rounding loss onto the protocol. In the worst case, `totalBorrow.base` can reach zero while `totalBorrow.elastic` remains positive, creating permanent orphan debt that no borrower can ever repay.",
    "paths": [
      "Spread debt across many small accounts, make them liquidatable, and batch them in one `liquidate()` call so each per-user `toElastic(..., false)` rounds down."
    ]
  },
  {
    "id": "F-008",
    "severity": "High",
    "confidence": "low",
    "title": "Checkpoint-token reentrancy can corrupt liquidation accounting",
    "locations": [
      "cauldrons/CauldronV4.sol:580",
      "cauldrons/CauldronV4.sol:581",
      "cauldrons/CauldronV4.sol:591",
      "cauldrons/CauldronV4.sol:592",
      "cauldrons/CauldronV4.sol:607",
      "cauldrons/PrivilegedCheckpointCauldronV4.sol:23",
      "cauldrons/PrivilegedCheckpointCauldronV4.sol:29"
    ],
    "claim": "In `PrivilegedCheckpointCauldronV4`, `_beforeUserLiquidated()` performs an external `user_checkpoint()` call before the outer liquidation updates `userBorrowPart`, `userCollateralShare`, and global totals. The outer function also caches `availableBorrowPart`/`borrowPart` before that call, so a reentrant checkpoint token can liquidate the same user again against stale locals.",
    "impact": "A malicious or compromised checkpoint token can desynchronize per-user debt from `totalBorrow`, double-process liquidation state, or force liquidation attempts to revert. That can translate into bad debt, broken accounting, or unliquidatable insolvent accounts.",
    "paths": [
      "Use a collateral token whose `user_checkpoint()` reenters `liquidate()` on the same victim during `PrivilegedCheckpointCauldronV4.liquidate()`."
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
