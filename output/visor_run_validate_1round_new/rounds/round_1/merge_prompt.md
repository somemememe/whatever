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
    "title": "Anyone can steal VISR from any EOA that has approved the hypervisor",
    "locations": [
      "contracts/RewardsHypervisor.sol:43",
      "contracts/RewardsHypervisor.sol:60",
      "contracts/RewardsHypervisor.sol:64"
    ],
    "claim": "The EOA branch of `deposit` never verifies that `msg.sender` is authorized to spend `from`'s VISR. Any attacker can call `deposit(visrDeposit, victim, attacker)` and use the victim's existing allowance to the hypervisor to move the victim's VISR into the pool while minting the corresponding `vVISR` shares to themselves.",
    "impact": "Any approved VISR balance can be permissionlessly converted into attacker-owned shares and then redeemed back out as VISR, resulting in direct theft of user funds.",
    "paths": [
      "Victim approves `RewardsHypervisor` to spend VISR",
      "Attacker calls `deposit(amount, victim, attacker)`",
      "Hypervisor pulls VISR from victim and mints `vVISR` to attacker",
      "Attacker calls `withdraw` on those shares to extract the victim's VISR"
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "Malicious visor contracts can mint completely unbacked shares",
    "locations": [
      "contracts/RewardsHypervisor.sol:56",
      "contracts/RewardsHypervisor.sol:58",
      "contracts/RewardsHypervisor.sol:64"
    ],
    "claim": "For contract depositors, `deposit` trusts `IVisor(from).delegatedTransferERC20(...)` without checking that any VISR was actually received. A malicious contract can return the attacker from `owner()` and make `delegatedTransferERC20` a no-op, yet still receive freshly minted `vVISR` for an arbitrary `visrDeposit`.",
    "impact": "An attacker can mint an overwhelming share balance with zero backing and then redeem those shares for nearly all VISR already held by the hypervisor, causing catastrophic pool theft and likely leaving honest share holders insolvent.",
    "paths": [
      "Attacker deploys a fake `IVisor` whose `owner()` returns the attacker and whose `delegatedTransferERC20` does nothing",
      "Attacker calls `deposit(veryLargeAmount, fakeVisor, attacker)`",
      "Hypervisor mints shares based on the claimed amount despite receiving no VISR",
      "Attacker withdraws the unbacked shares to drain the pool's real VISR"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "First depositor can seize all VISR that reaches the hypervisor before initialization",
    "locations": [
      "contracts/RewardsHypervisor.sol:50",
      "contracts/RewardsHypervisor.sol:51",
      "contracts/RewardsHypervisor.sol:80"
    ],
    "claim": "When `vvisr.totalSupply() == 0`, `deposit` mints shares 1:1 with `visrDeposit` and ignores any VISR balance already sitting in the hypervisor. If VISR is transferred in before the first mint, the first depositor can contribute a tiny amount, receive all initial shares, and then withdraw the entire pre-seeded balance.",
    "impact": "Any VISR accidentally sent, pre-funded, or otherwise accumulated in an uninitialized hypervisor can be stolen almost entirely by the first depositor.",
    "paths": [
      "VISR is transferred directly to the hypervisor before any `vVISR` exists",
      "Attacker makes a dust-sized first deposit",
      "Attacker receives the full initial share supply",
      "Attacker withdraws those shares and captures the pre-existing VISR plus their dust deposit"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "Donation-based inflation attack can make victims deposit for zero or too few shares",
    "locations": [
      "contracts/RewardsHypervisor.sol:52",
      "contracts/RewardsHypervisor.sol:53",
      "contracts/RewardsHypervisor.sol:64"
    ],
    "claim": "Share minting uses floor division against the current pool balance and provides no `minShares` or slippage protection. An attacker who already owns shares can donate VISR directly to the hypervisor to inflate `visr.balanceOf(address(this))`, causing a victim's subsequent deposit to mint zero or severely underpriced shares while still transferring the victim's VISR in full.",
    "impact": "A frontrunner can steal all or part of targeted deposits: the victim's VISR becomes a donation to existing shareholders, and the attacker later redeems their shares for the victim's assets.",
    "paths": [
      "Attacker acquires a small initial share position",
      "Attacker donates VISR directly to the hypervisor to skew the asset/share ratio",
      "Victim deposits without any minimum-share protection and receives zero or too few `vVISR`",
      "Attacker withdraws their shares and captures the victim's deposited VISR"
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
