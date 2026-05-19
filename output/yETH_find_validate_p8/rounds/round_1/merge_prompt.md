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
    "confidence": "medium",
    "title": "Liquidity operations appear to settle against stale cached rates",
    "locations": [
      "yETH.sol:104",
      "yETH.sol:109",
      "yETH.sol:143",
      "yETH.sol:149",
      "yETH.sol:223",
      "yETH.sol:232",
      "yETH.sol:236",
      "yETH.sol:241"
    ],
    "claim": "The exploit flow shows `update_rates` is a separate external step rather than something enforced inside `add_liquidity` / `remove_liquidity`, so core mint/burn accounting can execute while pool rates are stale.",
    "impact": "If deposits and withdrawals use outdated basket prices, an attacker can mint yETH while assets are undervalued and redeem after a later sync for more underlying than they contributed, leading to insolvency and full-pool loss.",
    "paths": [
      "Accumulate stale pricing by letting basket rates drift while repeatedly calling `add_liquidity` / `remove_liquidity` without a fresh sync",
      "Refresh rates only after the attacker has positioned the pool",
      "Redeem inflated yETH against the newly synced, more favorable basket"
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "medium",
    "title": "Caller-chosen partial rate updates can create mixed stale/fresh basket valuation",
    "locations": [
      "yETH.sol:38",
      "yETH.sol:40",
      "yETH.sol:159",
      "yETH.sol:161",
      "yETH.sol:179",
      "yETH.sol:181",
      "yETH.sol:193",
      "yETH.sol:195",
      "yETH.sol:236",
      "yETH.sol:241"
    ],
    "claim": "The rate-refresh API accepts an attacker-selected subset of asset indexes, and the exploit updates only asset 6 or 7 at carefully chosen moments, implying the invariant can be recomputed with a mixture of fresh and stale prices.",
    "impact": "Non-atomic repricing across a multi-asset pool lets an attacker reshape virtual balances in their favor, then withdraw more valuable assets against underpriced liabilities; this is sufficient for catastrophic drain.",
    "paths": [
      "Manipulate pool balances using adds/removes while most assets remain on old rates",
      "Call `update_rates` for only one targeted asset index",
      "Exploit the inconsistent basket valuation in the next withdrawal"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "`remove_liquidity(0)` appears to be stateful and usable as a free accounting checkpoint",
    "locations": [
      "yETH.sol:159",
      "yETH.sol:164",
      "yETH.sol:179",
      "yETH.sol:184",
      "yETH.sol:193",
      "yETH.sol:195",
      "yETH.sol:228",
      "yETH.sol:233"
    ],
    "claim": "The exploit invokes `remove_liquidity(0, ...)` three separate times immediately before profitable rate updates and follow-on withdrawals, which strongly suggests a zero-share burn is not a no-op and can mutate internal accounting for free.",
    "impact": "A zero-cost state transition lets an attacker reset checkpoints or rescale virtual balances without risking capital, making the subsequent over-withdrawal primitive much easier to repeat until the pool is drained.",
    "paths": [
      "Prepare pool state with imbalanced deposits",
      "Call `remove_liquidity(0)` to trigger the hidden accounting transition",
      "Refresh a targeted rate and perform the next oversized withdrawal"
    ]
  },
  {
    "id": "F-004",
    "severity": "Critical",
    "confidence": "medium",
    "title": "Rebasing OETH integration appears unsafely synchronized with pool accounting",
    "locations": [
      "yETH.sol:43",
      "yETH.sol:45",
      "yETH.sol:167",
      "yETH.sol:173"
    ],
    "claim": "The exploit explicitly triggers `OETH.rebase()` in the middle of the liquidity sequence, indicating the pool holds a rebasing asset whose externally changing balance can diverge from the pool's internal virtual-balance/rate accounting.",
    "impact": "If rebases are not fully incorporated before minting or redemption, an attacker can capture value that should belong to all LPs or use the stale post-rebase state to extract unrelated pool assets, causing direct theft.",
    "paths": [
      "Trigger `OETH.rebase()` so the pool's actual OETH balance changes exogenously",
      "Immediately add liquidity while internal accounting is still based on the pre-rebase state",
      "Later redeem from the pool after the mismatch has been converted into favorable yETH accounting"
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
