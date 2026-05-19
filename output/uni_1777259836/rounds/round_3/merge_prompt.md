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
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "high",
    "title": "Anyone can permissionlessly trigger the hardcoded exploit once the contract is funded",
    "locations": [
      "FlawVerifier.sol:29",
      "FlawVerifier.sol:44",
      "FlawVerifier.sol:51"
    ],
    "claim": "`executeOnOpportunity()` is fully permissionless even though it spends the contract's prefunded ETH/WETH and irreversibly mutates the fixed target pair by syncing corrupted balances and swapping out nearly all WETH reserves. There is no owner check or designated executor.",
    "impact": "A bot or griefing third party can front-run the intended operator, fire the exploit at an arbitrary time, and consume the one-shot opportunity through this contract. That strips the operator of execution control and can permanently leave the target pair drained while all resulting value remains trapped in the contract.",
    "paths": [
      "The operator funds the contract so `IWETH.deposit{value: 1 wei}()` can succeed",
      "A third party observes the funded balance and calls `executeOnOpportunity()` first",
      "The function syncs the manipulated reserves and drains the pair's WETH side, so later calls no longer face the same profitable state"
    ],
    "round": 2,
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
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "Any ERC20 sent to `FlawVerifier` is permanently unrecoverable",
    "locations": [
      "FlawVerifier.sol:29",
      "FlawVerifier.sol:61",
      "FlawVerifier.sol:69"
    ],
    "claim": "`FlawVerifier` has no token-sweep or withdrawal path for arbitrary ERC20s; it only unwraps whatever WETH balance happens to exist during `executeOnOpportunity()` and never exposes any way to transfer other tokens back out.",
    "impact": "Any ERC20 accidentally transferred to the contract, dusted into it by an attacker, or stranded there by an unexpected execution path is locked forever. If meaningful value is sent to the contract, the loss is permanent.",
    "paths": [
      "User or integrator transfers an ERC20 directly to `FlawVerifier`",
      "The contract receives a non-WETH token during some external interaction",
      "No function exists to move that token back out"
    ]
  },
  {
    "id": "F-005",
    "severity": "Low",
    "confidence": "high",
    "title": "Counter state is globally mutable by any address",
    "locations": [
      "Counter.sol:7",
      "Counter.sol:11"
    ],
    "claim": "`setNumber()` and `increment()` are fully unrestricted, so any external account can arbitrarily overwrite or advance `number`.",
    "impact": "If `Counter` is used as a trusted counter, flag, or dependency for offchain automation or other contracts, any attacker can corrupt that state and invalidate downstream assumptions.",
    "paths": [
      "Attacker calls `setNumber()` with any chosen value",
      "Attacker repeatedly calls `increment()` to force arbitrary state changes"
    ]
  },
  {
    "id": "F-006",
    "severity": "Low",
    "confidence": "low",
    "title": "Hardcoded external addresses make execution unsafe outside the intended deployment environment",
    "locations": [
      "FlawVerifier.sol:26",
      "FlawVerifier.sol:27",
      "FlawVerifier.sol:32",
      "FlawVerifier.sol:69"
    ],
    "claim": "`FlawVerifier` blindly trusts fixed `TARGET_PAIR` and `WETH` addresses and never verifies chain ID or contract code, so any deployment where those addresses resolve to different contracts will execute arbitrary external code and value flows against unintended targets.",
    "impact": "On a fork, testnet, or accidental cross-chain deployment, prefunded ETH can be trapped, execution can be spoofed or bricked, and the verifier can interact with attacker-controlled contracts while assuming they are the canonical pair and WETH.",
    "paths": [
      "Deploy `FlawVerifier` on a network where `TARGET_PAIR` or `WETH` is not the intended mainnet contract",
      "Call `executeOnOpportunity()`",
      "The contract performs trusted calls and value transfers against the wrong external contracts"
    ]
  },
  {
    "id": "F-007",
    "severity": "Low",
    "confidence": "high",
    "title": "Hardcoded 0.1 ETH profit floor rejects smaller but still profitable opportunities",
    "locations": [
      "FlawVerifier.sol:66"
    ],
    "claim": "`executeOnOpportunity()` hard-reverts unless the post-execution ETH balance increases by at least `0.1 ether`, with no configurability and no relation to actual gas cost or available edge.",
    "impact": "Any opportunity that is genuinely profitable but yields less than 0.1 ETH becomes unexecutable. After reserves shrink, the verifier can become permanently unusable even when positive-value extractions still exist.",
    "paths": [
      "A valid execution would net less than `0.1 ether`",
      "The final `require` at `FlawVerifier.sol:66` reverts",
      "The opportunity is discarded despite being profitable"
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
