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
    "title": "Referenced staking proxy appears mintable without supplying backing assets",
    "locations": [
      "FlawVerifier.sol:29",
      "FlawVerifier.sol:38",
      "FlawVerifier.sol:50",
      "FlawVerifier.sol:73",
      "FlawVerifier.sol:82"
    ],
    "claim": "The exploit encoded in `executeOnOpportunity()` relies on `TARGET_PROXY` exposing a reachable `mint(uint256,address)` path that issues mpETH shares before collecting equivalent assets from the caller. If that behavior exists on the referenced proxy, any attacker can mint unbacked shares and immediately swap them for ETH from the liquid unstake pool.",
    "impact": "Unbacked share issuance would dilute honest holders and enable direct theft of ETH from the public liquid unstake pool, potentially draining all immediately available pool liquidity in a single transaction.",
    "paths": [
      "Call `executeOnOpportunity()`",
      "Read `liquidUnstakePool()` from `TARGET_PROXY`",
      "Call `IStakingLike(TARGET_PROXY).mint(desiredShares, address(this))` without first transferring assets",
      "Approve the pool to spend the freshly minted mpETH",
      "Call `swapmpETHforETH()` to cash out the unbacked shares for ETH"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "low",
    "title": "Balance-based funding checks on the referenced proxy can be bypassed with forced ETH transfers",
    "locations": [
      "FlawVerifier.sol:20",
      "FlawVerifier.sol:23",
      "FlawVerifier.sol:67",
      "FlawVerifier.sol:69",
      "FlawVerifier.sol:141"
    ],
    "claim": "The verifier’s attack path explicitly tops up `TARGET_PROXY` via `selfdestruct` before minting, which indicates the referenced system may trust raw native-token balance (`TARGET_PROXY.balance`) or similar balance-derived checks instead of strictly accounted deposits. If so, forced ETH transfers can satisfy internal funding assumptions without going through the protocol’s intended deposit/accounting flow.",
    "impact": "An attacker could bypass deposit invariants, satisfy asset-availability checks that were meant to require a real user-funded deposit, and combine that with the mint path to extract ETH or otherwise desynchronize accounting from actual credited deposits.",
    "paths": [
      "Compute `shortfall = _fundingShortfall(...)`",
      "Deploy `ForceEther` funded with exactly the shortfall",
      "Call `ForceEther.boom(TARGET_PROXY)` to push ETH into the target without invoking its normal flow",
      "Invoke `mint()` after the forced top-up so the target observes enough balance to proceed"
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
