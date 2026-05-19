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
    "severity": "Critical",
    "confidence": "high",
    "title": "New deposits can capture rewards accrued before they were staked",
    "locations": [
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:118",
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:121",
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:125",
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:130",
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:131"
    ],
    "claim": "Blacksmith.deposit() snapshots the pool and bonus accumulators before calling updatePool(), then uses those stale values for reward claims and writeoffs. A fresh depositor therefore avoids being charged for rewards accrued before their deposit and can later claim a share of historical COVER and bonus emissions.",
    "impact": "An attacker can wait until a pool has accumulated substantial unclaimed rewards, deposit a very large amount immediately before claiming, and steal most of the rewards that should belong to existing stakers.",
    "paths": [
      "Let a pool accrue rewards without interactions",
      "Deposit a large amount via deposit()",
      "Because rewardWriteoff/bonusWriteoff are computed from stale accumulators, call claimRewards() and receive rewards from before the deposit"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Shared bonus-token accounting lets one pool drain another pool's bonus reserves",
    "locations": [
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:217",
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:233",
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:266",
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:327"
    ],
    "claim": "The contract does not enforce global uniqueness for bonus-token addresses across pools, yet both bonus claims and bonus-dust collection transfer from the contract's entire balance of that ERC20. If the same bonus token is attached to multiple pools, payouts or sweeps from one pool consume reserves backing the others.",
    "impact": "Users in one pool can deplete bonus tokens owed to users in another pool, and once one pool's grace period elapses any caller can send the entire shared bonus-token balance to treasury, breaking active bonus programs elsewhere.",
    "paths": [
      "Owner allows bonus token X",
      "Partners add bonus token X to pool A and pool B",
      "Users in pool A claim bonuses or anyone calls collectBonusDust(poolA)",
      "Pool B becomes underfunded because both pools share the same token balance"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "SAFE2 migrations can exceed the advertised migration cap",
    "locations": [
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Migrator.sol:27",
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Migrator.sol:49",
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Migrator.sol:63"
    ],
    "claim": "migrationCap is enforced only in claim(), not in migrateSafe2(). If merkle claims consume the remaining cap first, later SAFE2 holders can still migrate and mint additional COVER beyond the cap.",
    "impact": "Total migration minting can exceed the intended supply cap, causing unbounded inflation relative to the documented migration limits and diluting all COVER holders.",
    "paths": [
      "Eligible claimants use claim() until safe2Migrated + safeClaimed is near migrationCap",
      "A SAFE2 holder then calls migrateSafe2()",
      "migrateSafe2() mints without any cap check, pushing total migrated supply above migrationCap"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "Deposits over-credit fee-on-transfer or deflationary LP tokens",
    "locations": [
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:128",
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:133",
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:153"
    ],
    "claim": "Blacksmith credits miner.amount by the requested _amount before measuring how many LP tokens were actually received. For fee-on-transfer, rebasing, or otherwise deflationary tokens, a depositor can receive more stake credit than the contract actually holds.",
    "impact": "If such a token is ever whitelisted as an LP token, attackers can overstate their stake, over-earn COVER/bonus rewards, and withdraw value that was actually supplied by other stakers.",
    "paths": [
      "Deposit a taxed/deflationary LP token",
      "Receive credit for the full _amount while Blacksmith receives less",
      "Claim rewards on the inflated position or withdraw more than was actually deposited"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "Reward-parameter changes apply retroactively to already elapsed time",
    "locations": [
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:169",
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:173",
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:272",
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Blacksmith.sol:291"
    ],
    "claim": "updatePoolWeights() and updateWeeklyTotal() mutate emission parameters without checkpointing pools first, while _calculateCoverRewardsForPeriod() applies the current weight and weeklyTotal to the entire time since lastUpdatedAt. Parameter changes therefore rewrite past accrual, not just future accrual.",
    "impact": "Governance can redirect already-earned COVER emissions away from honest pools and toward favored pools by changing weights or weeklyTotal immediately before any pool update or harvest.",
    "paths": [
      "Allow rewards to accrue without calling updatePool()",
      "Change a pool's weight or weeklyTotal",
      "Update and harvest the favored pool",
      "Past rewards are computed using the new parameters"
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "high",
    "title": "Team vesting can release arbitrary ERC20s, not just COVER",
    "locations": [
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Vesting.sol:38",
      "onchain_auto/0xe0b94a7bb45dd905c79bb1992c9879f40f1caed5/contracts/Vesting.sol:46"
    ],
    "claim": "Vesting.vest() accepts an arbitrary IERC20 parameter and transfers that token to the beneficiary according to the COVER vesting schedule. The contract never binds vesting to a specific COVER token address.",
    "impact": "Any ERC20 accidentally or intentionally sent to the vesting contract can be drained by the listed beneficiary wallets, even if the asset was not meant to vest.",
    "paths": [
      "Transfer any ERC20 to Vesting",
      "A whitelisted beneficiary calls vest(arbitraryToken)",
      "The contract transfers that arbitrary token out using the COVER vesting schedule"
    ]
  }
]

```

### Agent: opencode_1
```
I'll audit the smart contracts in the specified directory. Let me read all the contract files to find security vulnerabilities.
Let me read all the contract files:
Now let me read the main contracts:
Let me continue reading the other contracts:
Let me continue reading more files:
Now I have analyzed all the contracts. Let me compile the security findings:

[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Migrator can change itself and mint unlimited COVER tokens",
    "locations": ["COVER.sol:40-45"],
    "claim": "The setMigrator function allows the current migrator to change the migrator address to any address including itself without any additional verification.",
    "impact": "Once the migrator is set (via the release function), the migrator can call setMigrator with their own address, then call mint() to create unlimited COVER tokens, causing infinite inflation and complete protocol failure.",
    "paths": ["1. Wait for release() to set migrator address", "2. Call setMigrator(msg.sender) to make self the migrator", "3. Call mint() with any amount to create unlimited tokens"]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Fee-on-transfer tokens cause deposit loss",
    "locations": ["Blacksmith.sol:115-135"],
    "claim": "The deposit function records the deposited amount as _amount but does not account for tokens that take a transfer fee (fee-on-transfer tokens).",
    "impact": "If a user deposits a fee-on-transfer token (e.g., USDT, USDC), the actual balance received will be less than the recorded amount. The user's recorded balance will be inflated while the actual deposited value is lower, causing permanent loss of deposited tokens.",
    "paths": ["1. User approves a fee-on-transfer token", "2. User calls deposit() with amount X", "3. Token transfer takes fee Y, only X-Y arrives", "4. Contract records X, but only has X-Y", "5. User loses Y tokens"]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Emergency withdraw loses pending rewards",
    "locations": ["Blacksmith.sol:158-166"],
    "claim": "The emergencyWithdraw function immediately transfers the user's staked tokens without first claiming any pending COVER or bonus token rewards.",
    "impact": "Users calling emergencyWithdraw forfeit all their unclaimed COVER and bonus tokens. These rewards are not transferred to the user and remain in the contract, effectively being stolen by the protocol.",
    "paths": ["1. User has staked tokens with pending rewards", "2. User calls emergencyWithdraw", "3. Staked tokens are returned but pending rewards are lost"]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "medium",
    "title": "BitMap index overflow potential in Migrator",
    "locations": ["Migrator.sol:41-47"],
    "claim": "The isSafeClaimed function uses bit shifting (1 << claimedBitIndex) without bounds checking on claimedBitIndex (derived from _index % 256).",
    "impact": "If _index exceeds reasonable bounds, the bit shift could cause unexpected behavior. While the Merkle proof likely constrains the index, this is a potential vulnerability if the merkle root is manipulated.",
    "paths": ["1. Submit claim with extremely large _index", "2. Bit operation may overflow or behave unexpectedly"]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Precision loss in reward calculations",
    "locations": ["Blacksmith.sol:60-61,66-67,84,90,291"],
    "claim": "The reward calculation divides coverRewards by lpTotal before accumulating, causing truncation and precision loss.",
    "impact": "Small deposits may lose their reward share due to integer division truncation. Over time, this accumulates and users receive less than their fair share of rewards.",
    "paths": ["1. User deposits small amount into large pool", "2. Division causes truncation of rewards", "3. User receives less than expected"]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Missing nonReentrant on vesting function",
    "locations": ["Vesting.sol:38-47"],
    "claim": "The vest function performs an external call (token.safeTransfer) without the nonReentrant modifier.",
    "impact": "If the token's transfer function triggers a callback to the Vesting contract, an attacker could re-enter the vest function and claim multiple times in a single transaction, draining the contract.",
    "paths": ["1. Malicious token calls back into vest() during transfer", "2. Attacker claims multiple times in single transaction"]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Claim function allows any caller to claim on behalf of any address",
    "locations": ["Migrator.sol:59-73"],
    "claim": "The claim function does not verify that msg.sender is the beneficiary specified in the Merkle proof. It only verifies the proof but allows anyone to trigger the claim for any address.",
    "impact": "While the Merkle proof ensures only the rightful owner can claim their specific amount, anyone can trigger the claim transaction for any address, potentially causing griefing or front-running issues.",
    "paths": ["1. Observe pending claim in mempool", "2. Front-run with higher gas to claim for victim", "3. Victim's claim fails as already claimed"]
  },
  {
    "id": "F-008",
    "severity": "Low",
    "confidence": "high",
    "title": "Weekly total can be set to zero causing reward halt",
    "locations": ["Blacksmith.sol:272-274"],
    "claim": "The updateWeeklyTotal function allows governance to set weeklyTotal to any value including zero without any checks.",
    "impact": "Governance could set weeklyTotal to 0, completely halting all COVER token rewards for all pools. While this requires governance compromise, it represents a centralization risk.",
    "paths": ["1. Governance calls updateWeeklyTotal(0)", "2. All reward distributions halt permanently"]
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
