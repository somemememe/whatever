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
    "severity": "High",
    "confidence": "high",
    "title": "Signed orders can be replayed and overfilled indefinitely",
    "locations": [
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:487",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:613"
    ],
    "claim": "`fillOrder` never checks whether `sFilledFraction[orderHash]` is already non-zero or whether a new fill would exceed 100%, so the same signed order can be executed repeatedly with `fraction == 1e18`.",
    "impact": "A taker can reuse one signature to force the maker into the same trade multiple times, consuming the maker's token allowances/balances and creating far more exposure than the maker authorized.",
    "paths": [
      "Maker signs one order for a single fill",
      "Taker calls `fillOrder(order, signature, 1e18)` once",
      "Because no filled-status check exists, the taker calls the same function again with the same inputs",
      "Each replay repeats upfront-token transfers and fresh long/short minting"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Anyone can manipulate settlement by delaying start/end snapshots away from the target window",
    "locations": [
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/interfaces/ISilicaPools.sol:193",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:396",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:409",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:442",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:456",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:856",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:874"
    ],
    "claim": "The interface says end-state accounting must be prorated to the target time range, but the implementation simply snapshots `index.balance()` and `index.shares()` at the actual keeper call times and uses those raw values for payout calculation.",
    "impact": "An economically interested actor can wait to call `startPool` and/or `endPool` until the index path favors their long or short position, materially changing who receives the pool collateral and potentially flipping the winning side entirely.",
    "paths": [
      "A pool reaches `targetStartTimestamp`, but nobody starts it immediately",
      "An attacker first acquires the side that benefits from excluding early performance",
      "The attacker calls `startPool` late, fixing `indexInitialBalance` at a manipulated/favorable time",
      "The attacker later calls `endPool` at a similarly favorable time",
      "Redemption uses the delayed raw snapshots instead of the promised target-window performance"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Pools on non-monotonic indices can become permanently unendable",
    "locations": [
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/interfaces/ISilicaIndex.sol:69",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/libraries/PoolMaths.sol:87",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/libraries/PoolMaths.sol:89",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:454"
    ],
    "claim": "`ISilicaIndex` explicitly allows `balance()` to decrease over time, but `grossBalanceChangePerShare` hard-reverts unless `indexBalance >= indexInitialBalance`, and `endPool` depends on that function.",
    "impact": "If the tracked index ever moves down over the pool term, `endPool` can never succeed, `actualEndTimestamp` stays zero forever, and separated long/short holders cannot redeem their positions, leaving collateral effectively trapped.",
    "paths": [
      "Pool is started while `indexInitialBalance` is recorded",
      "Index balance decreases before maturity",
      "Any caller attempts `endPool`",
      "`PoolMaths.grossBalanceChangePerShare` reverts, so the pool never reaches the ended state",
      "All `redeemLong` / `redeemShort` calls remain blocked by `actualEndTimestamp == 0`"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "Fee-on-transfer or rebasing payout tokens make pools insolvent",
    "locations": [
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:824",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:826",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:828",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:904"
    ],
    "claim": "`_collateralizedMint` increases `sState.collateralMinted` by the nominal collateral amount before/without checking how many payout tokens were actually received, so transfer-tax or rebasing tokens break the accounting invariant between recorded collateral and real balance.",
    "impact": "The contract can mint fully collateralized-looking long/short shares while holding less than the amount owed. Refunds, bounties, or redemptions later fail or leave later redeemers with losses because the pool is underfunded.",
    "paths": [
      "A pool uses a payout token that burns or taxes transfers",
      "A mint/fill transfers `collateral`, but the contract receives less than `collateral`",
      "`sState.collateralMinted` still records the full nominal amount",
      "Later `collateralRefund`, `redeemLong`, or `redeemShort` attempts rely on inflated accounting and eventually exceed the contract's real token balance"
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "Fresh exposure can still be minted after the market outcome is partly or fully known",
    "locations": [
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:509",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:512",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:817"
    ],
    "claim": "Both `fillOrder` and `_collateralizedMint` only reject pools whose `actualEndTimestamp` is already set; they do not stop issuance after `targetStartTimestamp`, after the pool has started, or even after `targetEndTimestamp` has passed but before someone finalizes the pool.",
    "impact": "A taker can wait until a large portion of the index path is already revealed—or until the entire target period has elapsed but `endPool` has not yet been called—then fill stale orders at pre-discovery terms and extract value from the maker with much lower risk.",
    "paths": [
      "Maker signs an order before or near pool start",
      "The target window progresses and the index path becomes informative or fully known",
      "Before `endPool` is called, the attacker fills the stale order because `actualEndTimestamp` is still zero",
      "The attacker immediately holds newly minted exposure priced off old assumptions, then settles after finalization"
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "high",
    "title": "Emergency pause does not stop direct minting, settlement, refunds, or redemption",
    "locations": [
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:138",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:162",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:396",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:442",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:661",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:686",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:710",
      "0xf3f84ce038442ae4c4dcb6a8ca8bacd7f28c9bde/contracts/SilicaPools.sol:488"
    ],
    "claim": "The `paused` flag is enforced only inside `fillOrder`; the other state-changing entry points continue to operate normally while the protocol is paused.",
    "impact": "During an incident, the owner cannot actually freeze the system. Attackers can bypass the pause by calling direct minting, pool start/end, collateral refunds, or redemptions, reducing the usefulness of the emergency control exactly when it is needed most.",
    "paths": [
      "Owner calls `pause()` expecting to halt the protocol",
      "An attacker or arbitrary user calls `collateralizedMint`, `startPool`, `endPool`, `collateralRefund`, `redeemLong`, or `redeemShort` directly",
      "The transaction succeeds because none of those functions check `paused`"
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
