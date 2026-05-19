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
    "title": "Unsafe delegatecall path allows arbitrary wallet storage corruption",
    "locations": [
      "Bybit.sol:189",
      "Bybit.sol:193",
      "Bybit.sol:194"
    ],
    "claim": "`changeMasterCopy` submits a Safe transaction as `DelegateCall` to a caller-chosen contract using attacker-controlled calldata, with no validation that the target code is storage-compatible or trusted. Because delegatecall executes in the wallet's storage context, a malicious target can overwrite privileged proxy state such as the implementation pointer.",
    "impact": "If signers approve a malicious transaction, the wallet can be permanently taken over and all assets can be stolen. This is a full-compromise primitive rather than a one-off call bug.",
    "paths": [
      "changeMasterCopy -> IMultisigWallet.execTransaction(..., DelegateCall, ...) -> attacker-controlled code executes in wallet storage",
      "phished signers approve benign-looking calldata -> delegatecall mutates wallet state instead of performing an external transfer"
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "Slot-0 storage collision in Trojan replaces the proxy implementation",
    "locations": [
      "Bybit.sol:287",
      "Bybit.sol:291",
      "Bybit.sol:292"
    ],
    "claim": "`Trojan` stores `masterCopy` in storage slot 0 and its `transfer` function writes the attacker-supplied `to` address into that slot. When this function is reached via delegatecall from the wallet proxy, the write lands in the proxy's own slot 0, replacing its implementation/masterCopy with attacker code.",
    "impact": "A single successful delegatecall turns the wallet into an attacker-controlled proxy permanently, so every later fallback-routed call executes the backdoor implementation and owner protections are effectively bypassed.",
    "paths": [
      "execTransaction(delegatecall to Trojan) -> Trojan.transfer(backdoor, 0) -> wallet slot0 overwritten with backdoor address"
    ]
  },
  {
    "id": "F-003",
    "severity": "Critical",
    "confidence": "high",
    "title": "Backdoor implementation exposes unrestricted ETH and token sweeping",
    "locations": [
      "Bybit.sol:299",
      "Bybit.sol:304",
      "Bybit.sol:305"
    ],
    "claim": "`Backdoor.sweepETH` and `Backdoor.sweepERC20` are public and perform no authentication before transferring the entire ETH or ERC20 balance to an arbitrary destination. Once the proxy's implementation is redirected to `Backdoor`, any caller can invoke these functions through the proxy fallback and drain funds.",
    "impact": "After implementation hijack, theft is permissionless and complete: all ETH and supported ERC20 balances can be moved to an attacker-controlled address in a single call.",
    "paths": [
      "wallet fallback -> Backdoor.sweepETH(destination) -> full ETH drain",
      "wallet fallback -> Backdoor.sweepERC20(token, destination) -> full token drain"
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
