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
    "title": "Caller-controlled router target and calldata let anyone drain third-party ERC20 allowances",
    "locations": [
      "Contract.sol:22",
      "Contract.sol:25",
      "Contract.sol:37",
      "Contract.sol:40",
      "Contract.sol:96",
      "Contract.sol:106",
      "Contract.sol:117",
      "Contract.sol:128"
    ],
    "claim": "`routerCallNative` exposes both the external call target (`_params.router`) and raw calldata (`_data`) to the caller. The exploit sets `router` to the USDC token itself and encodes `transferFrom(victim, attacker, amount)`, so the Rubic proxy becomes a public ERC20 spender for every user that has approved it.",
    "impact": "Any externally owned account can steal the balances of arbitrary victims up to their allowance to the Rubic proxy, causing direct and immediate loss of funds without needing victim interaction.",
    "paths": [
      "Choose a victim that approved the Rubic proxy for USDC",
      "Set `_params.router` to the USDC token address",
      "Encode `_data = transferFrom(victim, attacker, min(balance, allowance))`",
      "Call `routerCallNative(...)` so the proxy executes the token call as the approved spender"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "medium",
    "title": "Integrator identity is caller-supplied, enabling impersonation of trusted integrators",
    "locations": [
      "Contract.sol:21",
      "Contract.sol:36",
      "Contract.sol:51",
      "Contract.sol:95",
      "Contract.sol:105"
    ],
    "claim": "The privileged `integrator` value is taken directly from calldata and reused by the exploit through a hard-coded third-party integrator address. This means any trust, fee treatment, or allowlisting attached to an integrator can be borrowed by an arbitrary caller unless the implementation authenticates `msg.sender` separately.",
    "impact": "An attacker can masquerade as a whitelisted or otherwise trusted integrator to unlock restricted execution paths, bypass policy checks, and amplify fund-theft or routing abuse that should only be available to vetted integrator infrastructure.",
    "paths": [
      "Discover any accepted integrator address",
      "Populate `_params.integrator` with that trusted address",
      "Submit the transaction from an unrelated attacker EOA",
      "Reuse the trusted integrator context to access the dangerous router execution path"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "The native-call entrypoint can be invoked with zero input and zero recipient checks, turning it into a free arbitrary-call gadget",
    "locations": [
      "Contract.sol:25",
      "Contract.sol:40",
      "Contract.sol:89",
      "Contract.sol:90",
      "Contract.sol:94",
      "Contract.sol:99",
      "Contract.sol:100",
      "Contract.sol:104",
      "Contract.sol:118",
      "Contract.sol:129"
    ],
    "claim": "The exploit succeeds through `routerCallNative` even though `srcInputToken`, `srcInputAmount`, and `recipient` are all zeroed. That indicates the native bridge entrypoint is not enforcing native-value semantics or binding the declared transfer parameters to the executed call, so it can be abused without depositing assets.",
    "impact": "Attackers can reach the router execution path at zero cost, bypass the normal asset-intake/accounting assumptions of a bridge flow, and use the proxy as a generic execution primitive for theft or denial-of-service against approved users.",
    "paths": [
      "Call `routerCallNative` with `srcInputAmount = 0` and no `msg.value`",
      "Leave `recipient` and other transfer-description fields unset",
      "Provide malicious call data anyway",
      "Obtain privileged external execution despite no legitimate native swap or bridge input"
    ]
  }
]

```



## Excluded From Direct Audit Scope
Do not keep findings whose reportable root cause exists solely in files matching:
- `out/**`

Those files may still be read as context for in-scope implementation code.


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
