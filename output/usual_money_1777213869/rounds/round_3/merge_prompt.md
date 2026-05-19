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
    "severity": "High",
    "confidence": "medium",
    "title": "Untrusted external calls can recursively reenter the public strategy entrypoint",
    "locations": [
      "FlawVerifier.sol:96",
      "FlawVerifier.sol:347",
      "FlawVerifier.sol:352",
      "FlawVerifier.sol:357",
      "FlawVerifier.sol:362",
      "FlawVerifier.sol:392"
    ],
    "claim": "The contract makes many unconstrained calls into the hard-coded target while `executeOnOpportunity()` remains publicly callable and unguarded by any reentrancy mutex, so the target can call back into `executeOnOpportunity()` mid-run and start nested executions against partially changed balances and live approvals.",
    "impact": "A reentering target can force unbounded recursion until out-of-gas or trigger duplicated probe/liquidation logic while funds are in-flight, turning a single call into a treasury-burning denial of service and making the prefunded balance unrecoverable in practice.",
    "paths": [
      "executeOnOpportunity -> _probeEcosystem -> _call0(TARGET, ...) -> TARGET reenters executeOnOpportunity()",
      "executeOnOpportunity -> _probeSelectors -> _attempt(...) -> TARGET reenters executeOnOpportunity()"
    ]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Max approvals to the target persist after execution and expose future balances",
    "locations": [
      "FlawVerifier.sol:141",
      "FlawVerifier.sol:216",
      "FlawVerifier.sol:217",
      "FlawVerifier.sol:299",
      "FlawVerifier.sol:300",
      "FlawVerifier.sol:406"
    ],
    "claim": "The strategy repeatedly grants `type(uint256).max` allowances to `TARGET` and never revokes them, leaving USD0/USUAL balances spendable by the target contract outside the intended execution window.",
    "impact": "If the target has any token-pull code path, is upgradeable, or is later compromised, leftover or newly transferred USD0/USUAL can be drained in a later transaction without any fresh approval from FlawVerifier.",
    "paths": [
      "executeOnOpportunity -> _probeEcosystem -> _forceApprove(USD0, TARGET, max) / _forceApprove(USUAL, TARGET, max) -> allowance remains live after return",
      "executeOnOpportunity -> _tryCycle -> _forceApprove(USD0, TARGET, max) -> future USD0 balance becomes pullable by TARGET"
    ]
  },
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "low",
    "title": "Profit signals are spoofable because anyone can inject ETH/WETH during execution",
    "locations": [
      "FlawVerifier.sol:102",
      "FlawVerifier.sol:126",
      "FlawVerifier.sol:152",
      "FlawVerifier.sol:153",
      "FlawVerifier.sol:418",
      "FlawVerifier.sol:419"
    ],
    "claim": "The contract infers success from raw balance changes, but it keeps no internal accounting baseline and freely accepts ETH through `receive()`/`fallback()`, while `_tryCycle()` trusts the final WETH balance without proving that the increase came from the attempted arbitrage itself.",
    "impact": "A losing strategy can be made to look profitable by donating ETH/WETH during the run, which can fool any balance-based verifier or operator into accepting treasury-burning executions as successful.",
    "paths": [
      "executeOnOpportunity -> _attemptMintArbCycles -> _tryCycle -> external callee transfers WETH to FlawVerifier -> `wethAfter > wethBefore + ethIn` passes despite a lossy cycle",
      "third party sends ETH to FlawVerifier via `receive()`/`fallback()` before a balance-based post-check and masks net losses"
    ]
  },
  {
    "id": "F-010",
    "severity": "Medium",
    "confidence": "low",
    "title": "Unbounded returndata copies let a malicious target brick execution with a return-data bomb",
    "locations": [
      "FlawVerifier.sol:130",
      "FlawVerifier.sol:131",
      "FlawVerifier.sol:132",
      "FlawVerifier.sol:397",
      "FlawVerifier.sol:399",
      "FlawVerifier.sol:411",
      "FlawVerifier.sol:413"
    ],
    "claim": "Helpers such as `_safeBalanceOf()` and `_safeApprove()` copy arbitrary returndata from external contracts into memory without any size cap, so a malicious or nonstandard callee can return an enormous blob and force memory expansion/OOG.",
    "impact": "A single hostile response from `TARGET` or any interacted token can make strategy execution revert consistently, creating a practical denial of service over the prefunded treasury with no on-contract recovery path.",
    "paths": [
      "executeOnOpportunity -> _tryCycle -> _safeBalanceOf(TARGET, address(this)) -> TARGET returns oversized data -> out-of-gas",
      "executeOnOpportunity -> _liquidateToken -> _forceApprove(token, spender, max) -> malicious token returns oversized data -> out-of-gas"
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
