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
    "title": "All prefunded ETH and extracted profits are permanently locked in the contract",
    "locations": [
      "FlawVerifier.sol:29",
      "FlawVerifier.sol:61",
      "FlawVerifier.sol:74"
    ],
    "claim": "The contract accepts ETH through `receive`/`fallback` and converts harvested WETH back into ETH, but it exposes no withdrawal, sweep, or beneficiary mechanism to move either ETH or tokens back out.",
    "impact": "Any ETH used to seed the strategy, any accidental ETH transfers, and any successful exploit proceeds become permanently irrecoverable. This creates total loss of all value that ever accumulates in the contract.",
    "paths": [
      "A user prefunds the contract so `IWETH.deposit{value: 1 wei}()` can execute",
      "A successful run unwraps WETH into the contract via `IWETH.withdraw`",
      "No external function exists to transfer the ETH/WETH back to an operator"
    ]
  },
  {
    "id": "F-002",
    "severity": "Medium",
    "confidence": "high",
    "title": "Forced ETH donations can permanently brick `executeOnOpportunity`",
    "locations": [
      "FlawVerifier.sol:30",
      "FlawVerifier.sol:66",
      "FlawVerifier.sol:74"
    ],
    "claim": "Profitability is checked against `address(this).balance`, so any third party can increase the required profit threshold by sending or force-sending ETH to the contract; because that ETH cannot be withdrawn, the inflated baseline is sticky.",
    "impact": "An attacker can permanently deny execution once the trapped balance exceeds the strategy's maximum extractable profit plus the hardcoded `0.1 ether` threshold. This makes the contract unusable even if the external market opportunity still exists.",
    "paths": [
      "An attacker sends or force-sends ETH to the contract",
      "The extra ETH increases `initialBalance` at the start of `executeOnOpportunity`",
      "The final `require(address(this).balance >= initialBalance + 0.1 ether)` becomes impossible to satisfy"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "low",
    "title": "Hardcoded external addresses are used without chain or code validation",
    "locations": [
      "FlawVerifier.sol:26",
      "FlawVerifier.sol:27",
      "FlawVerifier.sol:32"
    ],
    "claim": "The contract blindly trusts two hardcoded addresses as a Uniswap pair and WETH instance without verifying `block.chainid`, code existence, or expected runtime code before making privileged external calls.",
    "impact": "If this bytecode is deployed on any chain or fork where those addresses are absent or controlled by different code, `executeOnOpportunity` can call arbitrary contracts, leading to permanent lockup, unexpected reverts, or value being routed into attacker-controlled code.",
    "paths": [
      "Deploy the contract on a network other than the intended Ethereum mainnet environment",
      "Call `executeOnOpportunity` so the contract invokes `token0`, `token1`, `sync`, `swap`, `deposit`, `transfer`, or `withdraw` on whatever code lives at the hardcoded addresses"
    ]
  },
  {
    "id": "F-004",
    "severity": "Low",
    "confidence": "high",
    "title": "Counter state is fully mutable by any caller",
    "locations": [
      "Counter.sol:7",
      "Counter.sol:11"
    ],
    "claim": "Both `setNumber` and `increment` are unrestricted public mutators, so any address can arbitrarily rewrite or advance the contract's only piece of state.",
    "impact": "If any surrounding system relies on `number` for sequencing, authorization, accounting, or configuration, an arbitrary user can corrupt that logic at will. In isolation this contract only loses integrity, but the state is completely untrusted.",
    "paths": [
      "Any external account calls `setNumber` with an arbitrary value",
      "Any external account repeatedly calls `increment` to change the state"
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
