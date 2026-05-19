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
    "title": "Blind low-level probing with persistent approvals can self-inflict irreversible token loss",
    "locations": [
      "FlawVerifier.sol:141",
      "FlawVerifier.sol:156",
      "FlawVerifier.sol:282",
      "FlawVerifier.sol:299",
      "FlawVerifier.sol:300",
      "FlawVerifier.sol:347",
      "FlawVerifier.sol:392",
      "FlawVerifier.sol:406"
    ],
    "claim": "The verifier grants large allowances to external contracts, leaves those allowances in place, and then issues many guessed low-level calls against `TARGET`, `USD0`, and `USUAL` while discarding success flags and enforcing no post-call safety invariant. If any probed selector or later token-pull path resolves to live state-changing logic, approved balances can be silently transferred, burned, or locked without the verifier detecting the loss.",
    "impact": "A matching selector on one of the fixed external contracts can permanently burn, transfer away, or lock the verifier's assets during execution, and any surviving `USD0`/`USUAL` balances remain exposed afterward because the `TARGET` approvals are never revoked.",
    "paths": [
      "Call `executeOnOpportunity()` so `_probeEcosystem()` and `_probeSelectors()` run.",
      "The verifier first sets broad approvals for `TARGET`.",
      "One probed selector or later `TARGET` code path uses those approvals against the verifier's balances.",
      "The external call succeeds and the verifier continues without reverting or checking for unexpected balance loss."
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "high",
    "title": "Hard-coded Ethereum mainnet endpoints can burn the treasury on the wrong chain",
    "locations": [
      "FlawVerifier.sol:74",
      "FlawVerifier.sol:80",
      "FlawVerifier.sol:96",
      "FlawVerifier.sol:134",
      "FlawVerifier.sol:241"
    ],
    "claim": "The contract hard-codes Ethereum mainnet token and router addresses but never verifies `block.chainid` or that those endpoints are the intended contracts before sending value and interacting with them. In particular, `_tryCycle()` sends native currency to the hard-coded `WETH` address through `deposit()` with no code or chain check.",
    "impact": "If `FlawVerifier` is deployed or replayed on a different EVM network, its funded native-token treasury can be irreversibly transferred to an unrelated EOA or noncanonical contract at the same address, or otherwise routed through arbitrary endpoints instead of real WETH/Uniswap infrastructure.",
    "paths": [
      "Deploy `FlawVerifier` on any non-Ethereum-mainnet EVM chain.",
      "Fund it with native currency and call `executeOnOpportunity()`.",
      "`_tryCycle()` executes `IWETH(WETH).deposit{value: ethIn}()` against the hard-coded address, sending treasury funds to whatever exists there on that chain."
    ],
    "round": 2,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "medium",
    "title": "No end-to-end profit check lets losing executions complete successfully",
    "locations": [
      "FlawVerifier.sol:89",
      "FlawVerifier.sol:96",
      "FlawVerifier.sol:97",
      "FlawVerifier.sol:101",
      "FlawVerifier.sol:201",
      "FlawVerifier.sol:282"
    ],
    "claim": "Although the contract comment states the final balance must exceed the initial balance, `executeOnOpportunity()` never snapshots starting balances or reverts on an overall net loss. Only `_tryCycle()` enforces a local WETH-profit condition; the surrounding probe and liquidation stages can still make state-changing calls, incur adverse conversions, and return successfully even when the contract finishes poorer than it started.",
    "impact": "A caller can finalize treasury-burning runs that leave the verifier with less native-token value than it began with, so unsuccessful or partially harmful probe/liquidation sequences become permanent instead of reverting atomically.",
    "paths": [
      "Fund the contract and call `executeOnOpportunity()` when no genuine profitable opportunity exists.",
      "`_probeEcosystem()` and `_probeSelectors()` perform speculative external calls anyway.",
      "`_liquidateAll()` converts any resulting balances under the available execution paths.",
      "The function returns successfully even if the contract's final native-token-equivalent balance is below its starting balance."
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
    "id": "F-007",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Native-balance based success can be spoofed with third-party ETH donations",
    "locations": [
      "FlawVerifier.sol:96",
      "FlawVerifier.sol:102",
      "FlawVerifier.sol:418",
      "FlawVerifier.sol:419"
    ],
    "claim": "The contract accepts arbitrary ETH via `receive()`/`fallback()` and keeps no internal accounting of funded principal versus externally donated ETH, so any success condition based on the contract's ending native balance can be satisfied by outside transfers instead of real trading profit.",
    "impact": "A losing or no-op execution can be made to look profitable by force-sending ETH before the verifier checks the post-run balance. That can produce false positives, waste treasury funds on bad strategies, or trigger downstream reward/acceptance logic on fabricated gains.",
    "paths": [
      "An attacker or colluding caller sends ETH directly to `FlawVerifier` after it is funded and before or during execution.",
      "`executeOnOpportunity()` completes without tracking the source of the balance increase.",
      "Any off-chain or wrapper logic that only compares starting and ending ETH balances accepts the run as profitable even if the strategy itself lost money."
    ]
  },
  {
    "id": "F-008",
    "severity": "High",
    "confidence": "low",
    "title": "Missing reentrancy guard exposes the treasury to callback-driven recursive execution",
    "locations": [
      "FlawVerifier.sol:96",
      "FlawVerifier.sol:121",
      "FlawVerifier.sol:347",
      "FlawVerifier.sol:357",
      "FlawVerifier.sol:392",
      "FlawVerifier.sol:418"
    ],
    "claim": "The contract makes a large number of raw external calls and token approvals while holding a 1,000,000-native-token treasury, but it has no reentrancy lock or execution-state guard to stop `TARGET`, `USD0`, `USUAL`, or any upgradeable/token callback path from reentering `executeOnOpportunity()` or otherwise nesting execution mid-strategy.",
    "impact": "If any called external contract can call back into `FlawVerifier`, an attacker can recurse into the strategy while intermediate balances and approvals are live, compounding risky swaps, invalidating the local balance assumptions in `_tryCycle`, exhausting gas, or draining significantly more treasury value than a single pass should risk.",
    "paths": [
      "A probed target/token function executes arbitrary code during `_attempt`, `_call0`, `_call1`, `_call2`, or approval handling.",
      "That callback invokes `executeOnOpportunity()` again before the outer invocation finishes.",
      "Nested runs reuse the same treasury and allowances, causing repeated liquidation/probing/swapping from an inconsistent intermediate state."
    ]
  },
  {
    "id": "F-009",
    "severity": "Low",
    "confidence": "high",
    "title": "Counter state is fully mutable by any external account",
    "locations": [
      "Counter.sol:7",
      "Counter.sol:11"
    ],
    "claim": "`setNumber()` and `increment()` are both public and unrestricted, so any address can arbitrarily overwrite or mutate the contract's only piece of state.",
    "impact": "The contract provides no state integrity at all. Any integration that treats `number` as trusted state can be manipulated by arbitrary users, breaking authorization, accounting, or control-flow assumptions built on top of it.",
    "paths": [
      "An arbitrary account calls `setNumber()` to assign any value.",
      "An arbitrary account calls `increment()` repeatedly to change the stored value over time."
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
