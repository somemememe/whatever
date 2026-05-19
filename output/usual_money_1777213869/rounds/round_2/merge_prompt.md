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
    "title": "ETH and residual token balances can be permanently trapped in FlawVerifier",
    "locations": [
      "FlawVerifier.sol:96",
      "FlawVerifier.sol:102",
      "FlawVerifier.sol:418",
      "FlawVerifier.sol:419"
    ],
    "claim": "The contract can receive native tokens through `receive`/`fallback` and can accumulate ERC20 balances during probing and liquidation, but `executeOnOpportunity()` only unwraps WETH back into ETH held by the same contract. There is no code path anywhere in the contract that transfers ETH or ERC20 balances out to an operator or recovery address.",
    "impact": "Any ETH used to fund the verifier, together with any profits or residual ERC20 balances it acquires, can become permanently unrecoverable. In the documented deployment model, the pre-funded treasury can be locked forever inside the contract.",
    "paths": [
      "Fund `FlawVerifier` with native tokens.",
      "Call `executeOnOpportunity()` so the contract probes, swaps, and may end with ETH/WETH or other ERC20 balances.",
      "Observe that no withdrawal or sweep function exists to move those assets out of the contract."
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
    "title": "Anyone can execute the full treasury strategy without authorization",
    "locations": [
      "FlawVerifier.sol:96",
      "FlawVerifier.sol:97",
      "FlawVerifier.sol:101"
    ],
    "claim": "`executeOnOpportunity()` is `external` and has no access control, caller validation, cooldown, or one-shot guard, so any account can trigger the entire probing, mint-arbitrage, and liquidation routine against whatever assets the contract currently holds.",
    "impact": "A third party can force the verifier to deploy its treasury at attacker-chosen times, reopen the strategy whenever the contract is re-funded, and generally grief the operator or pre-position MEV around the contract's full balance.",
    "paths": [
      "Wait until the contract is funded.",
      "Call `executeOnOpportunity()` from any EOA or contract.",
      "Repeat the call whenever the contract is funded again or still holds tradable balances."
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-003",
    "severity": "Critical",
    "confidence": "high",
    "title": "All swaps use zero minimum output, enabling price-manipulation extraction",
    "locations": [
      "FlawVerifier.sol:241",
      "FlawVerifier.sol:266",
      "FlawVerifier.sol:384"
    ],
    "claim": "Every live Uniswap V2 and V3 swap path sets `amountOutMin`/`amountOutMinimum` to zero and performs no independent price or slippage validation before trading the contract's full token balance.",
    "impact": "An MEV searcher can manipulate the relevant pool immediately before execution, let the verifier trade at an arbitrarily bad rate, then back-run to restore price and capture most of the treasury value as profit.",
    "paths": [
      "Observe a pending `executeOnOpportunity()` transaction or call it directly after funding.",
      "Manipulate one of the pools used by `_swapV3All()` or `_swapV2Path()`.",
      "Let the verifier execute swaps with zero slippage protection.",
      "Back-run the pool to unwind the manipulation and keep the extracted value."
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "low",
    "title": "Blind low-level probing after approvals can self-inflict irreversible token loss",
    "locations": [
      "FlawVerifier.sol:141",
      "FlawVerifier.sol:156",
      "FlawVerifier.sol:282",
      "FlawVerifier.sol:347",
      "FlawVerifier.sol:392",
      "FlawVerifier.sol:406"
    ],
    "claim": "The verifier grants large allowances to external contracts and then issues many guessed low-level calls against `TARGET`, `USD0`, and `USUAL` while discarding success flags and enforcing no post-call safety invariant. If any probed selector resolves to a live state-changing method, the contract can silently trigger approved token pulls, burns, or other destructive transitions.",
    "impact": "A matching selector on one of the fixed external contracts can permanently burn, transfer away, or lock the verifier's assets, and the verifier will continue execution without detecting the loss.",
    "paths": [
      "Call `executeOnOpportunity()` so `_probeEcosystem()` and `_probeSelectors()` run.",
      "The verifier first sets broad approvals for external spenders.",
      "One probed selector happens to map to a live function with side effects on the verifier's approved balances or held assets.",
      "The external call succeeds and the verifier continues without reverting or checking for unexpected balance loss."
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
    "severity": "Critical",
    "confidence": "high",
    "title": "Hard-coded Ethereum mainnet endpoints can burn the entire treasury on the wrong chain",
    "locations": [
      "FlawVerifier.sol:74",
      "FlawVerifier.sol:80",
      "FlawVerifier.sol:96",
      "FlawVerifier.sol:134",
      "FlawVerifier.sol:241"
    ],
    "claim": "The contract hard-codes Ethereum mainnet token/router addresses but never verifies block.chainid or that critical endpoints are the expected contracts before sending value and interacting with them. In particular, _tryCycle() sends native currency to the hard-coded WETH address through deposit() without any code or chain check.",
    "impact": "If the contract is deployed or replayed on the wrong network, its 1,000,000 native-token treasury can be irreversibly transferred to unrelated EOAs/contracts at those same addresses, or otherwise routed through arbitrary noncanonical endpoints.",
    "paths": [
      "Deploy FlawVerifier on any non-Ethereum-mainnet EVM chain",
      "Fund it with native currency and call executeOnOpportunity()",
      "_tryCycle() executes IWETH(WETH).deposit{value: ethIn}() against the hard-coded address, transferring treasury funds to whatever exists there on that chain"
    ]
  },
  {
    "id": "F-006",
    "severity": "High",
    "confidence": "medium",
    "title": "No top-level profit invariant allows permanently unprofitable execution",
    "locations": [
      "FlawVerifier.sol:96",
      "FlawVerifier.sol:97",
      "FlawVerifier.sol:99",
      "FlawVerifier.sol:101",
      "FlawVerifier.sol:201",
      "FlawVerifier.sol:282"
    ],
    "claim": "executeOnOpportunity() never snapshots starting balances or reverts on overall net loss, even though it performs many speculative external calls and forced liquidation steps. Only _tryCycle() has a local WETH-profit check; the surrounding probe and liquidation stages can still commit losses and return successfully.",
    "impact": "A caller can finalize treasury-burning runs that lose funds through fees, adverse execution, partial state changes, or negative-value probe paths, despite the contract comment stating the final balance must exceed the initial balance.",
    "paths": [
      "Fund the contract and call executeOnOpportunity() when no genuinely profitable opportunity exists",
      "_probeEcosystem() and _probeSelectors() perform state-changing calls anyway",
      "_liquidateAll() converts resulting balances under whatever execution is available",
      "The function returns successfully even if the contract ends with less native-token value than it started with"
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "low",
    "title": "Arbitrary external calls are reentrancy-reachable while the contract holds funds and live approvals",
    "locations": [
      "FlawVerifier.sol:96",
      "FlawVerifier.sol:347",
      "FlawVerifier.sol:352",
      "FlawVerifier.sol:357",
      "FlawVerifier.sol:392",
      "FlawVerifier.sol:418"
    ],
    "claim": "The contract repeatedly calls external contracts via low-level call with no reentrancy guard, while simultaneously holding native currency/tokens and leaving large approvals in place. Any callee that can invoke executeOnOpportunity() or otherwise recurse back into FlawVerifier can force nested strategy execution on intermediate balances.",
    "impact": "Nested execution can multiply risky swaps/probes, reorder assumptions about available balances, and deepen losses or gas exhaustion beyond what a single run would incur.",
    "paths": [
      "During _probeSelectors(), _probeEcosystem(), or _attempt(), a called contract executes a callback into FlawVerifier",
      "The callback re-enters executeOnOpportunity() before the outer invocation finishes",
      "The nested run operates on partially processed balances and approvals, compounding exposure"
    ]
  },
  {
    "id": "F-008",
    "severity": "Low",
    "confidence": "high",
    "title": "Counter exposes unrestricted state mutation",
    "locations": [
      "Counter.sol:7",
      "Counter.sol:11"
    ],
    "claim": "Both setNumber() and increment() are publicly callable without any authorization or role checks, so any account can arbitrarily change the stored counter value.",
    "impact": "If any downstream system treats number as trusted state, its integrity is completely compromised because any user can overwrite or skew it at will.",
    "paths": [
      "Any external account calls setNumber(newValue)",
      "Any external account repeatedly calls increment()"
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
