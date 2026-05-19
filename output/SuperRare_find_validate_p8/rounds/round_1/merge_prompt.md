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
    "title": "Unrestricted `updateMerkleRoot()` lets any caller self-authorize arbitrary token claims",
    "locations": [
      "SuperRare.sol:68",
      "SuperRare.sol:70",
      "SuperRare.sol:77"
    ],
    "claim": "The target staking contract exposes `updateMerkleRoot(bytes32)` without effective access control. An attacker can set the root to `keccak256(abi.encodePacked(attacker, amount))`, then call `claim(amount, [])`; with an empty proof, the attacker-controlled leaf becomes the entire Merkle tree and validates immediately.",
    "impact": "Any external account can overwrite the active distribution root and drain the full RARE balance from the staking contract in a single transaction, causing direct theft of all tokens allocated to legitimate claimants/stakers.",
    "paths": [
      "AttackContract.attack -> IERC1967Proxy.updateMerkleRoot(fakeRoot) -> IERC1967Proxy.claim(stakingContractBalance, [])",
      "fakeRoot = keccak256(abi.encodePacked(ATTACK_CONTRACT, stakingContractBalance))"
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
