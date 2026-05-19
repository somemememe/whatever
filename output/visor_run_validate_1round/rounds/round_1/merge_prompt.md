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
    "title": "Anyone can steal approved EOA VISR by depositing from the victim into their own share account",
    "locations": [
      "contracts/RewardsHypervisor.sol:41",
      "contracts/RewardsHypervisor.sol:60",
      "contracts/RewardsHypervisor.sol:61",
      "contracts/RewardsHypervisor.sol:64"
    ],
    "claim": "The EOA deposit path never checks that `msg.sender` is authorized by `from`. Any caller can pass an arbitrary EOA as `from`; if that EOA has approved the hypervisor, `safeTransferFrom(from, address(this), visrDeposit)` pulls the victim's VISR while `vvisr.mint(to, shares)` mints the corresponding shares to the attacker's chosen `to` address.",
    "impact": "Any user who grants the hypervisor an allowance can have their approved VISR stolen permissionlessly. The attacker receives the full vVISR position and can later redeem the victim's principal plus any accrued rewards.",
    "paths": [
      "Victim approves `RewardsHypervisor` to spend VISR.",
      "Attacker calls `deposit(amount, victimEOA, attacker)`.",
      "Hypervisor transfers VISR from the victim and mints vVISR to the attacker.",
      "Attacker later calls `withdraw` to redeem the stolen position."
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "A fake `IVisor` contract can mint completely unbacked shares and drain all VISR",
    "locations": [
      "contracts/RewardsHypervisor.sol:50",
      "contracts/RewardsHypervisor.sol:56",
      "contracts/RewardsHypervisor.sol:57",
      "contracts/RewardsHypervisor.sol:58",
      "contracts/RewardsHypervisor.sol:64"
    ],
    "claim": "For contract depositors, the hypervisor trusts any address with code as an `IVisor` and only checks `IVisor(from).owner() == msg.sender`. It never verifies that `delegatedTransferERC20` actually transferred VISR, nor does it measure the balance delta. An attacker can supply a malicious contract whose `owner()` returns the attacker and whose `delegatedTransferERC20()` is a no-op, yet still receive freshly minted vVISR shares.",
    "impact": "An attacker can mint an arbitrarily large share balance without contributing any VISR, then withdraw a proportional amount of the real VISR held by the hypervisor, draining honest depositors completely.",
    "paths": [
      "Attacker deploys a contract implementing `owner()` and `delegatedTransferERC20()`.",
      "`owner()` returns the attacker; `delegatedTransferERC20()` does nothing.",
      "Attacker calls `deposit(hugeAmount, fakeVisor, attacker)`.",
      "Hypervisor mints shares as if VISR were received.",
      "Attacker calls `withdraw` and redeems the pool's real VISR."
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "The first depositor can seize any VISR already sitting in the hypervisor",
    "locations": [
      "contracts/RewardsHypervisor.sol:50",
      "contracts/RewardsHypervisor.sol:51",
      "contracts/RewardsHypervisor.sol:52",
      "contracts/RewardsHypervisor.sol:53",
      "contracts/RewardsHypervisor.sol:64"
    ],
    "claim": "When `vvisr.totalSupply() == 0`, the hypervisor always sets `shares = visrDeposit` and skips pricing against the existing VISR balance. If VISR has been transferred into the hypervisor before the first share mint, those pre-existing assets are not reflected in the initial share issuance.",
    "impact": "Whoever makes the first deposit can capture all pre-seeded VISR, including externally sent rewards or accidental transfers, by depositing a trivial amount and then withdrawing 100% of the pool.",
    "paths": [
      "VISR is sent to the hypervisor before any vVISR exists.",
      "Attacker makes the first deposit with a tiny `visrDeposit`.",
      "Because total supply is zero, the attacker receives shares 1:1 with their tiny deposit instead of against total assets.",
      "The attacker withdraws and receives the entire pre-existing VISR balance."
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "Share minting uses the requested deposit amount instead of the actual VISR received",
    "locations": [
      "contracts/RewardsHypervisor.sol:50",
      "contracts/RewardsHypervisor.sol:53",
      "contracts/RewardsHypervisor.sol:58",
      "contracts/RewardsHypervisor.sol:61",
      "contracts/RewardsHypervisor.sol:64"
    ],
    "claim": "The hypervisor computes `shares` from the user-supplied `visrDeposit` before transferring tokens and never recomputes from `balanceAfter - balanceBefore`. Any short transfer (for example, fee-on-transfer behavior, token-side burns, or a wrapper contract transferring less than requested) still receives full shares as though the full amount arrived.",
    "impact": "The pool becomes undercollateralized because depositors can receive more vVISR than the assets actually added. Those over-minted shares can later be redeemed against honest users' VISR.",
    "paths": [
      "A deposit route transfers less VISR than `visrDeposit` while not reverting.",
      "Hypervisor still mints shares based on the larger nominal amount.",
      "The depositor later withdraws using the inflated share balance, diluting or stealing from other holders."
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
