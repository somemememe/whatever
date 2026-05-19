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
    "title": "Unauthenticated proxy entrypoint can redirect custodied weETH to an arbitrary receiver",
    "locations": [
      "unverified_54cd.sol:43",
      "unverified_54cd.sol:46",
      "unverified_54cd.sol:65"
    ],
    "claim": "The PoC shows that a single external call to the live ERC1967 proxy using selector `0x03b79c24` and an attacker-chosen address is enough to obtain a large `weETH` balance, which is then immediately sold for `WETH`. This is strong evidence that the implementation exposes a privileged token-release/sweep path without effective authorization.",
    "impact": "Any attacker can drain protocol-held `weETH` from the proxy to an arbitrary address, converting it into liquid assets and causing direct loss of TVL.",
    "paths": [
      "Call proxy selector `0x03b79c24` with attacker-controlled recipient",
      "Receive protocol `weETH` on the attacker contract",
      "Swap drained `weETH` for `WETH` through the Uniswap V3 pool",
      "Withdraw `WETH` to ETH and transfer proceeds to the attacker"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "medium",
    "title": "Asset release path appears unbounded by per-user accounting",
    "locations": [
      "unverified_54cd.sol:43",
      "unverified_54cd.sol:51",
      "unverified_54cd.sol:58"
    ],
    "claim": "The abused proxy function appears to take only a recipient address, yet the attacker is able to extract enough value to settle a `106.929468097270451433`-sized Uniswap swap and cash out `114.534059890882021484` WETH. That strongly suggests the withdrawal/claim logic is not bounded by caller-specific shares, debt, or an explicit amount parameter, and instead can release an oversized or global balance.",
    "impact": "Even if the function was intended to be user-facing, broken accounting would let a caller withdraw far more than its legitimate entitlement, making reserve depletion and insolvency possible in a single call.",
    "paths": [
      "Invoke the proxy entrypoint with only a recipient argument",
      "Receive a protocol-sized `weETH` balance rather than a tightly bounded user amount",
      "Liquidate the extracted asset for `WETH` and realize the imbalance as profit"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "low",
    "title": "Sensitive maintenance or recovery selector appears left reachable on the asset-holding proxy",
    "locations": [
      "unverified_54cd.sol:22",
      "unverified_54cd.sol:43"
    ],
    "claim": "The exploit targets the ERC1967 proxy address directly with a raw, undocumented selector instead of a normal public ABI method. This pattern is consistent with a migration/recovery/initializer-style routine remaining callable in production through the proxy fallback, despite the proxy holding live funds.",
    "impact": "If operational-only logic is not permanently disabled after deployment, any forgotten selector reachable via proxy delegation can become a TVL-draining backdoor without needing further privilege escalation.",
    "paths": [
      "Send a crafted call with selector `0x03b79c24` to the proxy",
      "Reach a delegated implementation routine that should not be externally reachable in production",
      "Use that routine to extract or redirect the proxy's live asset balance"
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
