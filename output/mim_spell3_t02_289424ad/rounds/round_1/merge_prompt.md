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
None yet.

## This Round's Agent Outputs
### Agent: codex
```
[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Unsupported `cook` actions silently clear the deferred solvency check",
    "locations": [
      "cauldrons/CauldronV4.sol:456",
      "cauldrons/CauldronV4.sol:488",
      "cauldrons/CauldronV4.sol:527",
      "cauldrons/CauldronV4.sol:538"
    ],
    "claim": "The base `_additionalCookAction` implementation is an empty no-op that returns a zeroed `CookStatus` instead of reverting. After `ACTION_BORROW` or `ACTION_REMOVE_COLLATERAL` sets `needsSolvencyCheck = true`, any unsupported action (including the declared-but-unhandled `ACTION_ACCRUE`) overwrites `status` with all-false values, so `cook()` reaches the end without executing the final solvency check.",
    "impact": "An attacker can borrow MIM or remove collateral through `cook()` without remaining solvent. In practice this allows uncollateralized or undercollateralized borrowing up to the market's borrow caps and available MIM balance, creating immediate bad debt and enabling pool drains.",
    "paths": [
      "Call `cook([ACTION_BORROW, ACTION_ACCRUE], ...)` so `_borrow()` transfers out MIM, then the unhandled second action resets `needsSolvencyCheck` and the transaction finishes without the `require(_isSolvent(...))` guard.",
      "Call `cook([ACTION_REMOVE_COLLATERAL, <unsupported_action>], ...)` to withdraw collateral and then erase the pending solvency check before the loop ends."
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "A zero oracle rate is treated as valid, making dust-collateralized debt appear fully solvent",
    "locations": [
      "cauldrons/CauldronV4.sol:158",
      "cauldrons/CauldronV4.sol:201",
      "cauldrons/CauldronV4.sol:226",
      "cauldrons/CauldronV4.sol:578"
    ],
    "claim": "Both initialization and live price updates accept an `exchangeRate` of zero, and `_isSolvent()` multiplies debt by that rate. When the cached rate is zero, any account with `borrowPart > 0` and even 1 share of collateral satisfies the solvency check because the right-hand side becomes zero; liquidation also skips those accounts because it calls the same `_isSolvent()` predicate.",
    "impact": "If the oracle ever returns a zero price, an attacker can post dust collateral, borrow nearly all MIM liquidity, withdraw almost all collateral while leaving 1 share behind, and remain permanently 'solvent' and effectively unliquidatable. This can drain the market and strand protocol bad debt.",
    "paths": [
      "Oracle returns `(true, 0)` to `updateExchangeRate()`, caching `exchangeRate = 0`.",
      "Attacker adds minimal collateral, borrows available MIM, removes collateral down to 1 share, and cannot be liquidated because `liquidate()` sees the position as solvent at the zero rate."
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "`init()` ignores the oracle success flag and can seed a poisoned cached price",
    "locations": [
      "cauldrons/CauldronV4.sol:148",
      "cauldrons/CauldronV4.sol:158",
      "cauldrons/CauldronV4.sol:160",
      "cauldrons/CauldronV4.sol:233"
    ],
    "claim": "During clone initialization, `init()` stores the raw `rate` returned by `oracle.get(oracleData)` without checking the accompanying `success` boolean. A failing oracle response such as `(false, 0)` therefore seeds `exchangeRate` with zero or another invalid value, and later failed updates preserve that poisoned cache because `updateExchangeRate()` falls back to the old rate when `updated == false`.",
    "impact": "A newly deployed market can come online already carrying a broken cached price, making it immediately drainable or otherwise mis-priced until somebody manages to push a successful refresh. A transient oracle outage during deployment is enough to arm the bug.",
    "paths": [
      "Clone is deployed while the oracle returns `(false, 0)` during `init()`.",
      "Before any successful refresh happens, an attacker uses the poisoned cached price to borrow against negligible collateral or otherwise exploit the mispricing."
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "Risk actions continue against stale cached prices whenever the oracle update fails",
    "locations": [
      "cauldrons/CauldronV4.sol:218",
      "cauldrons/CauldronV4.sol:226",
      "cauldrons/CauldronV4.sol:233",
      "cauldrons/CauldronV4.sol:539"
    ],
    "claim": "If `oracle.get()` fails, `updateExchangeRate()` does not halt borrowing, collateral withdrawals, or liquidation logic; it simply reuses the previously cached `exchangeRate`. The normal `borrow()`, `removeCollateral()`, and `cook()` solvency checks all accept that stale value instead of requiring a fresh price.",
    "impact": "After a sharp collateral move during an oracle outage, borrowers can keep borrowing or withdrawing collateral against an outdated, overly favorable price. This can create large protocol bad debt and make liquidations lag the true market state.",
    "paths": [
      "Collateral market price drops materially off-chain.",
      "Oracle update fails, so `exchangeRate` stays at the older, higher cached value.",
      "Borrower calls `borrow()` or `cook()` and passes solvency checks at the stale valuation, extracting excess MIM or collateral."
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "low",
    "title": "Public clone initialization is first-come-first-served if deployment is ever non-atomic",
    "locations": [
      "cauldrons/CauldronV4.sol:146",
      "cauldrons/CauldronV4.sol:147",
      "cauldrons/CauldronV4.sol:148"
    ],
    "claim": "The clone initializer is fully public and only checks that `collateral` is still unset. If a clone is ever deployed without being initialized atomically in the same transaction, any external account can win the race to call `init()` first and choose the market's collateral, oracle, oracle data, and risk parameters.",
    "impact": "A hijacked clone can be permanently configured with a hostile oracle or unsafe parameters, turning the market into a drainable honeypot or bricking the intended deployment. The entire market instance would then be controlled by the attacker's initialization choices.",
    "paths": [
      "A clone address exists but is still uninitialized for any period of time.",
      "Attacker front-runs the intended initializer and calls `init()` with attacker-chosen collateral/oracle/parameters."
    ]
  }
]

```



## Excluded From Direct Audit Scope
Do not keep findings whose reportable root cause exists solely in files matching:
- `out/**`

Those files may still be read as context for in-scope implementation code.


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
