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
    "title": "Unchecked interaction offsets allow forged calldata to wrap into attacker-controlled settlement context",
    "locations": [
      "FlawVerifier.sol:87",
      "FlawVerifier.sol:89",
      "FlawVerifier.sol:426",
      "FlawVerifier.sol:439"
    ],
    "claim": "The forged payload deliberately supplies attacker-chosen signature/interaction offsets together with an enormous `FAKE_INTERACTION_LENGTH`; any settlement parser that trusts these values can seek outside the intended interaction blob and reinterpret attacker-supplied trailing bytes as the active order's final interaction.",
    "impact": "An attacker can redirect settlement parsing into forged trailer data and execute unauthorized asset movement using victim context, enabling direct theft rather than a mere revert.",
    "paths": [
      "Submit the payload returned by `_buildForgedSettlementPayload()` to `settleOrders`",
      "Use `FAKE_SIGNATURE_LENGTH_OFFSET`, `FAKE_INTERACTION_LENGTH_OFFSET`, and `FAKE_INTERACTION_LENGTH` to make parsing land on `finalOrderInteraction`",
      "Have settlement finalize using attacker-controlled trailer bytes instead of the real interaction payload"
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "medium",
    "title": "Historical victim authorization is replayable without fresh binding to the current order",
    "locations": [
      "FlawVerifier.sol:404",
      "FlawVerifier.sol:407",
      "FlawVerifier.sol:418"
    ],
    "claim": "The terminal forged interaction hardcodes `HISTORICAL_VICTIM`, `USDC`, and `AMOUNT_TO_STEAL` inside a synthetic suffix that is meant to mirror a previously trusted fill, showing that resolver/asset/amount context can be consumed without being freshly authenticated against the current order.",
    "impact": "Victim approvals or resolver context from an old fill can be replayed inside a new attacker-controlled settlement, allowing theft from historical makers/resolvers with no new signature or consent.",
    "paths": [
      "Forge `dynamicSuffix` with `HISTORICAL_VICTIM`, `USDC`, and `AMOUNT_TO_STEAL`",
      "Reach `FINALIZE_INTERACTION` through the corrupted parsing path",
      "Reuse the victim's historical approval/context to transfer funds in the attacker's new settlement"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Contract is a universal ERC1271 signer for arbitrary attacker-created orders",
    "locations": [
      "FlawVerifier.sol:162",
      "FlawVerifier.sol:177",
      "FlawVerifier.sol:234"
    ],
    "claim": "`isValidSignature` always returns the ERC1271 magic value, so any hash and any signature are accepted as authorized by this contract; the same contract later grants the limit-order protocol unlimited USDT allowance.",
    "impact": "Anyone can fabricate orders with `maker = address(this)` and drain all current or future USDT held by the contract through the approved protocol, because no real signature verification ever occurs.",
    "paths": [
      "Call `executeOnOpportunity()` once so `_prepareMakerCapital()` approves USDT to `LIMIT_ORDER_PROTOCOL`",
      "Create an arbitrary order naming this contract as maker and giving the attacker favorable terms",
      "Fill it through the limit-order protocol; `isValidSignature()` approves the fake signature and the protocol can pull the contract's USDT"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "Public zero-slippage swaps let MEV attackers extract nearly all traded value",
    "locations": [
      "FlawVerifier.sol:229",
      "FlawVerifier.sol:259",
      "FlawVerifier.sol:321"
    ],
    "claim": "`executeOnOpportunity` is permissionless and every AMM trade uses `amountOutMin = 1`, so callers or MEV searchers can manipulate the relevant Uniswap V2 pools immediately before execution and force the contract to trade at near-arbitrary prices.",
    "impact": "Any ETH or USDC the contract holds can be swapped at a ruinous rate, with the attacker recovering the value in the surrounding sandwich/backrun transactions.",
    "paths": [
      "Wait for the contract to hold ETH or USDC, or seed it yourself",
      "Skew the `WETH/USDT`, `USDC/USDT`, or `USDC/WETH` pool before calling `executeOnOpportunity()`",
      "Let the contract trade with `amountOutMin = 1`, then unwind the manipulation and keep the spread"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "Any user can permanently brick the one-shot execution path",
    "locations": [
      "FlawVerifier.sol:110",
      "FlawVerifier.sol:116",
      "FlawVerifier.sol:120"
    ],
    "claim": "The contract sets `_executed = true` before any of the external setup or settlement steps succeed, and there is no access control or reset mechanism.",
    "impact": "A front-runner can trigger the routine once in an unfunded or unfavorable state and permanently disable the core logic, preventing future execution and leaving later-deposited assets stranded in the contract.",
    "paths": [
      "Call `executeOnOpportunity()` before the intended operator has funded or timed the contract correctly",
      "Allow flash-seed or settlement steps to fail after `_executed` is already set",
      "Observe that all later calls only refresh profit and immediately return"
    ]
  },
  {
    "id": "F-006",
    "severity": "Low",
    "confidence": "low",
    "title": "Resolver hook is an always-successful no-op that validates nothing except caller address",
    "locations": [
      "FlawVerifier.sol:166",
      "FlawVerifier.sol:167"
    ],
    "claim": "`resolveOrders` only checks that `msg.sender` equals `SETTLEMENT` and ignores the `resolver`, `tokensAndAmounts`, and `data` arguments entirely, making this contract an always-successful resolver implementation.",
    "impact": "If this resolver address is ever used in settlement flows, it can act as a no-op authorization oracle and defeat assumptions that resolution data is being validated on-chain.",
    "paths": [
      "Reference this contract as a resolver in a settlement flow",
      "Have the settlement contract call `resolveOrders()` with attacker-chosen payload",
      "The hook returns successfully without enforcing any resolver-specific invariants"
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
