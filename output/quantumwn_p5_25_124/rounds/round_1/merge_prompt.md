Below are findings and vulnerability signals from 2 agents auditing the same codebase,
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
### Agent: codex_1
```
[
  {
    "id": "F-001",
    "severity": "High",
    "confidence": "medium",
    "title": "Unchecked ERC20 return values can mint unbacked stake receipts or release QWA without burning sQWA",
    "locations": [
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:65",
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:66",
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:74",
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:79"
    ],
    "claim": "The contract calls `transfer`/`transferFrom` on both `QWA` and `sQWA` but never checks their boolean return values. If either token signals failure by returning `false` instead of reverting, execution still continues, so `stake()` can hand out sQWA without receiving QWA and `unstake()` can send QWA without actually pulling in sQWA.",
    "impact": "A false-returning token implementation, paused token, blacklist, insufficient allowance path, or temporary transfer failure can directly create unbacked liabilities or let an attacker drain the staking pool. The inverse failure mode also confiscates user funds by taking payment without delivering the counter-asset.",
    "paths": [
      "Call `stake()` when `QWA.transferFrom(msg.sender, address(this), _amount)` returns `false`; the function still executes `sQWA.transfer(_to, _amount)` and mints claim tickets against no deposit.",
      "Call `unstake()` when `sQWA.transferFrom(msg.sender, address(this), _amount)` returns `false`; the function still reaches `QWA.transfer(_to, _amount)` and releases QWA for free."
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Missed epochs can be stolen by new stakers because `rebase()` only catches up one epoch per call",
    "locations": [
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:64",
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:83",
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:87",
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:100"
    ],
    "claim": "When the contract is several epochs behind, `rebase()` advances only one epoch (`epoch.end += epoch.length`) and then returns. Because `stake()` calls this single-step rebase before accepting a new deposit, an attacker can join after long inactivity but before the remaining overdue rebases are processed, then receive a pro-rata share of rewards that accrued entirely before they entered.",
    "impact": "Historical rewards meant for existing stakers can be diluted and captured by a late entrant. The larger the backlog, the larger the theft opportunity.",
    "paths": [
      "Wait until multiple epochs pass without any successful `rebase()` calls so excess QWA has accumulated for old stakers.",
      "Call `stake()` once; it processes only one overdue epoch and then accepts the attacker deposit.",
      "Call `rebase()` again until caught up, then `unstake()`; the attacker now owns a large share of the previously accrued backlog."
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "high",
    "title": "Predictable epoch boundaries allow just-in-time staking to siphon each epoch's reward",
    "locations": [
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:63",
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:72",
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:83",
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:95"
    ],
    "claim": "Rewards are distributed purely to whoever is in `sQWA.circulatingSupply()` at rebase time, and there is no warmup period, lockup, or time-weighting. A large holder can enter shortly before `epoch.end`, wait for the rebase, and leave immediately after, capturing most of that epoch's reward despite being exposed for only a minimal period.",
    "impact": "Long-term stakers are systematically diluted by short-term capital that only appears around epoch rollover, degrading reward fairness and letting sophisticated actors farm emissions at everyone else's expense.",
    "paths": [
      "Stake a very large amount shortly before `epoch.end`.",
      "Trigger or wait for the next `rebase()` so the temporary position is included in the reward split.",
      "Immediately call `unstake()` after the rebase to extract the disproportionate reward share."
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "low",
    "title": "Nominal-amount accounting breaks on fee-on-transfer or deflationary QWA and can leave the pool insolvent",
    "locations": [
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:65",
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:66",
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:79",
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:94"
    ],
    "claim": "The contract assumes the requested `_amount` is exactly what moved, but it never measures actual balance deltas. If QWA burns, taxes, or otherwise transfers less than `_amount`, `stake()` still gives out full `_amount` of sQWA while `rebase()` and `unstake()` continue to account off the nominal amount.",
    "impact": "Every taxed deposit can mint more sQWA than the pool actually received, creating immediate undercollateralization and pushing the loss onto existing stakers or future withdrawers. Reward calculations based on `balanceOf` are also distorted.",
    "paths": [
      "Deposit a fee-on-transfer QWA that only credits the staking contract with `amount - fee`.",
      "Receive the full `_amount` of sQWA anyway.",
      "Repeat deposits and later unstake to extract more QWA claim than was ever actually contributed."
    ]
  },
  {
    "id": "F-005",
    "severity": "Low",
    "confidence": "high",
    "title": "`secondsToNextEpoch()` reverts instead of reporting zero once an epoch is overdue",
    "locations": [
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:123",
      "0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:124"
    ],
    "claim": "The function returns `epoch.end - block.timestamp` directly. After the epoch has expired but before anyone calls `rebase()`, this subtraction underflows and reverts under Solidity 0.8.",
    "impact": "Off-chain systems, frontends, bots, and monitoring that rely on this view method can break exactly when the contract is overdue for a rebase.",
    "paths": [
      "Wait until `block.timestamp > epoch.end` without calling `rebase()`.",
      "Call `secondsToNextEpoch()`; the subtraction underflows and the view call reverts."
    ]
  }
]

```

### Agent: opencode_1
```
[{"id": "F-001", "severity": "High", "confidence": "high", "title": "Missing zero-address validation in constructor", "locations": ["0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:42-56"], "claim": "The constructor does not validate that _QWA and _sQWA addresses are non-zero", "impact": "If zero addresses are passed, the contract will malfunction - all stake/unstake operations will fail permanently as they rely on these immutable variables", "paths": ["Deploy with zero addresses, then attempt to stake"]}, {"id": "F-002", "severity": "High", "confidence": "high", "title": "Missing zero-address validation in setDistributor", "locations": ["0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:131-133"], "claim": "setDistributor allows setting distributor to zero address without validation", "impact": "Owner can accidentally set distributor to zero address, breaking reward distribution functionality permanently with no way to recover", "paths": ["Call setDistributor with address(0)"]}, {"id": "F-003", "severity": "High", "confidence": "medium", "title": "Missing reentrancy guard on stake function", "locations": ["0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:63-67"], "claim": "stake function makes external calls to token contracts without reentrancy protection", "impact": "If QWA or sQWA tokens are malicious or have callback hooks, reentrancy attack could drain funds or manipulate state", "paths": ["Implement malicious token with callback in transferFrom"]}, {"id": "F-004", "severity": "High", "confidence": "medium", "title": "Unstake with rebase can fail due to insufficient balance check", "locations": ["0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:72-80"], "claim": "When _rebase=true, unstake triggers rebase which may set distribute=0, then fails the balance check if contract has less QWA than staked", "impact": "Users cannot unstake their tokens when _rebase=true if the contract's QWA balance is less than the total sQWA in circulation, causing permanent fund lockup", "paths": ["Stake, wait for epoch to pass, then attempt unstake with _rebase=true"]}, {"id": "F-005", "severity": "Medium", "confidence": "high", "title": "Anyone can trigger rebase leading to MEV/front-running", "locations": ["0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:83-103"], "claim": "rebase() is public and can be called by anyone when epoch ends", "impact": "External bots can front-run rebase transactions, extracting MEV value. Also allows griefing by calling rebase multiple times to reset epoch timing", "paths": ["Monitor mempool for epoch end, front-run rebase calls"]}, {"id": "F-006", "severity": "Medium", "confidence": "medium", "title": "No access control allows anyone to stake to any address", "locations": ["0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:63-67"], "claim": "stake function allows staking QWA and minting sQWA to any arbitrary _to address", "impact": "Attacker can stake to any address (including contract addresses) to grief or manipulate accounting. Can cause unexpected behavior in protocols integrating with sQWA", "paths": ["Call stake with _to as a protocol contract address"]}, {"id": "F-007", "severity": "Low", "confidence": "high", "title": "Lack of event emission for setDistributor", "locations": ["0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:131-133"], "claim": "setDistributor does not emit an event when changing distributor address", "impact": "Makes it difficult to track off-chain changes to distributor, reducing transparency and making it harder to audit history", "paths": []}, {"id": "F-008", "severity": "Low", "confidence": "medium", "title": "Potential integer overflow in epoch.end update", "locations": ["0x69422c7f237d70fcd55c218568a67d00dc4ea068/contracts/Staking.sol:87"], "claim": "epoch.end = epoch.end + epoch.length uses addition without overflow check", "impact": "In extremely rare case where epoch runs for many years (2^256 seconds), overflow could cause epoch.end to wrap to 0, breaking rebase logic", "paths": ["Wait for epoch.end to reach 2^256 - epoch.length then call rebase"]}]

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
