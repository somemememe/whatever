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
    "severity": "High",
    "confidence": "high",
    "title": "All prefunded ETH and extracted profits are permanently locked in the contract",
    "locations": [
      "FlawVerifier.sol:29",
      "FlawVerifier.sol:61",
      "FlawVerifier.sol:74"
    ],
    "claim": "`executeOnOpportunity` relies on the contract already holding ETH so it can wrap `1 wei` into WETH, and later unwraps all harvested WETH back into raw ETH, but `FlawVerifier` exposes no withdrawal, sweep, or beneficiary-controlled transfer for either ETH or tokens.",
    "impact": "Any ETH used to seed the strategy, any accidental ETH sent to `receive`/`fallback`, and any successful exploit proceeds become permanently irrecoverable. This can trap the operator's capital and fully strand any profits inside the contract.",
    "paths": [
      "An operator or third party sends ETH to the contract so `IWETH.deposit{value: 1 wei}()` can succeed",
      "A successful run leaves value on the contract after `IWETH.withdraw(wethBal)` converts WETH into ETH",
      "No external function exists to move ETH or ERC20 balances out of the contract"
    ],
    "round": 1,
    "source_agents": [
      "codex"
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
    "claim": "Profitability is measured against `address(this).balance` at the start of each run, so anyone can raise the required profit threshold by sending or force-sending ETH to the contract. Because the contract has no withdrawal path, the inflated baseline cannot be reset.",
    "impact": "A griefing attacker can permanently make `executeOnOpportunity` fail once the trapped balance is high enough that the strategy cannot end with `initialBalance + 0.1 ether`. This creates a permissionless denial of service against the contract's only execution path.",
    "paths": [
      "An attacker transfers ETH to the contract or force-sends ETH via `SELFDESTRUCT`",
      "`executeOnOpportunity` snapshots the donated balance in `initialBalance`",
      "The final check `address(this).balance >= initialBalance + 0.1 ether` becomes unattainable, causing every call to revert"
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
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Anyone can front-run the exploit and consume the one-shot opportunity",
    "locations": [
      "FlawVerifier.sol:29"
    ],
    "claim": "`executeOnOpportunity()` is completely permissionless even though it spends this contract's prefunded balance against a fixed exploitable pair. Once the contract is funded, any third party can call the function first, drain the hardcoded pool through this contract, and irreversibly use up the opportunity before the intended operator acts.",
    "impact": "A searcher or griefing bot can steal the timing/control of the exploit, turning the contract into a public execution endpoint. Because the targeted pool can only be drained once and the proceeds remain trapped in the contract, the operator can permanently lose the entire recoverable value of the opportunity.",
    "paths": [
      "Operator prefunds the contract in one transaction",
      "A bot observes the new balance and immediately calls `executeOnOpportunity()` before the operator",
      "The pool is drained through this contract and later calls no longer have the same profitable state"
    ]
  },
  {
    "id": "F-004",
    "severity": "Low",
    "confidence": "high",
    "title": "Pre-existing WETH can spoof the profit check and make failed runs look successful",
    "locations": [
      "FlawVerifier.sol:30",
      "FlawVerifier.sol:61",
      "FlawVerifier.sol:66"
    ],
    "claim": "The contract snapshots only its starting ETH balance, but later unwraps and counts all WETH held by the contract as fresh profit. Any WETH that was already present before the call is not excluded from the profitability calculation.",
    "impact": "An execution can satisfy the `+0.1 ether` requirement even if the exploit itself produced no new value. This breaks the function's success invariant and can cause off-chain operators to treat an unprofitable or already-drained opportunity as successful while converting donated WETH into more permanently trapped ETH.",
    "paths": [
      "A user or attacker transfers at least `0.1 WETH` to the contract before execution",
      "Someone calls `executeOnOpportunity()` after the target opportunity is no longer profitable",
      "The function unwraps the pre-existing WETH and still passes `address(this).balance >= initialBalance + 0.1 ether`"
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
