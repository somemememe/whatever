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
    "severity": "Critical",
    "confidence": "high",
    "title": "Matured rewards can be claimed repeatedly by splitting withdrawals",
    "locations": [
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:118",
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:120",
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:213",
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:233"
    ],
    "claim": "`withdraw()` always computes `rewardAmount = getPendingRewards(msg.sender)` across every matured deposit before reducing principal, but the contract never records that rewards for a deposit were already paid. A user can therefore withdraw only a small slice of matured principal, receive the full matured reward for the entire position, keep most principal staked, and repeat until the pool is drained.",
    "impact": "A staker can extract the same matured reward many times and drain tokens owed to other users. For example, a fully vested 100-token deposit in the 40% tier can be withdrawn 1 token at a time and collect roughly the 40-token reward on each call until contract liquidity is exhausted.",
    "paths": [
      "Deposit into any tier and wait until the lock period expires",
      "Call `withdraw()` for a small amount of matured principal",
      "Receive that principal plus the full reward for all matured deposits",
      "Repeat partial withdrawals because no per-deposit reward-claimed state is ever updated"
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Rewards are paid from the same token pool that backs user principal, so early withdrawals can consume later deposits",
    "locations": [
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:95",
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:118",
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:125",
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:167",
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:210"
    ],
    "claim": "The contract accepts deposits and pays both principal and rewards in the same `rewardToken`, but it only tracks principal in `totalDeposits` and never reserves, escrows, or checks funding for accrued rewards. As a result, withdrawal payouts come directly from the shared token balance, which includes later users' principal.",
    "impact": "Even without exploiting another bug, normal rewarded withdrawals can make the pool insolvent and strand honest users' principal. Earlier users can effectively be paid using subsequent depositors' assets unless the owner continuously overfunds the contract off-chain.",
    "paths": [
      "User A deposits and waits for maturity",
      "User B and others deposit, increasing the contract's token balance",
      "User A withdraws and receives principal plus reward from the shared balance",
      "Remaining assets may fall below the outstanding principal owed to later users, causing their withdrawals to fail"
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Fee-on-transfer or deflationary tokens make internal balances exceed real assets",
    "locations": [
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:67",
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:100",
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:101",
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:167"
    ],
    "claim": "`deposit()` credits `_amount` to the user position and `totalDeposits` immediately after `safeTransferFrom`, but it never measures how many tokens were actually received. If the configured token burns fees, taxes transfers, or otherwise delivers less than requested, the contract records more principal than it owns from the first deposit onward.",
    "impact": "The pool becomes insolvent and can revert on later withdrawals because it owes more tokens than it actually holds. Pool-cap and position accounting are also overstated, compounding the mismatch.",
    "paths": [
      "Deploy the staking pool with a fee-on-transfer or deflationary ERC20",
      "A user deposits 100 tokens but the contract receives less than 100",
      "The contract still records a 100-token deposit and increments `totalDeposits` by 100",
      "Later withdrawals attempt to transfer more tokens than the contract balance contains"
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "Owner emergency withdrawal can seize all staked funds",
    "locations": [
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:246",
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:249",
      "0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:251"
    ],
    "claim": "`emergencyWithdraw()` lets the owner transfer any amount of the staking token to themselves, and passing `_amount == 0` withdraws the entire token balance. The function does not exclude user principal, does not preserve funds needed for pending withdrawals, and does not update `positions` or `totalDeposits` after removing assets.",
    "impact": "A malicious or compromised owner can drain all deposited tokens and permanently break user withdrawals while on-chain accounting still shows users as fully funded.",
    "paths": [
      "Users deposit tokens into the pool",
      "Owner calls `emergencyWithdraw(0)` or withdraws most of the balance",
      "The contract transfers user-backed assets to the owner without adjusting liabilities",
      "Users remain recorded as stakers but later withdrawals fail because the assets are gone"
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
    "severity": "High",
    "confidence": "high",
    "title": "Pool cap tracks only principal, so fixed reward promises can make the pool insolvent even without withdrawal games",
    "locations": [
      "onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:53",
      "onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:98",
      "onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:167",
      "onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:233"
    ],
    "claim": "The contract caps and accounts only `totalDeposits` (principal), but each matured deposit is owed `amount + reward`. Because rewards are not prefunded, reserved, or included in `MAX_POOL_CAP`, the protocol can become mathematically undercollateralized at steady state.",
    "impact": "At the default 40% tier, a full 10,000,000 token pool can owe 14,000,000 tokens after maturation while only ever receiving 10,000,000 tokens from stakers. If the owner does not inject the missing rewards, later withdrawals revert and users are left with locked funds.",
    "paths": [
      "Users fill the pool close to `MAX_POOL_CAP` through `deposit()`",
      "Rewards accrue via `_calculateRewards()` but no reserve is created",
      "When matured users call `withdraw()`, the contract must transfer principal plus rewards from a balance that may only contain principal"
    ]
  },
  {
    "id": "F-006",
    "severity": "High",
    "confidence": "medium",
    "title": "Owner-configurable external hook can permanently brick deposits and withdrawals through gas exhaustion",
    "locations": [
      "onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:95",
      "onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:104",
      "onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:138",
      "onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:242",
      "onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/interfaces/IPoolExtension.sol:5"
    ],
    "claim": "Every `deposit()` and `withdraw()` performs an owner-selected external call to `vaultExtension.setShare()` before updating staking state. Although normal reverts are caught, an extension that consumes all gas or otherwise OOGs causes the entire user operation to fail.",
    "impact": "A buggy or malicious extension can freeze all deposits and, more importantly, all withdrawals. If ownership is unavailable or the issue is not corrected quickly, user principal can remain locked indefinitely.",
    "paths": [
      "Owner sets a problematic contract via `setVaultExtension()`",
      "User calls `withdraw()` or `deposit()`",
      "`vaultExtension.setShare()` exhausts gas before returning, so `_updatePosition()` never reaches the internal accounting logic"
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "low",
    "title": "Swallowed extension failures can silently desynchronize staking balances from the external share ledger",
    "locations": [
      "onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:138",
      "onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:145",
      "onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/interfaces/IPoolExtension.sol:5"
    ],
    "claim": "If `vaultExtension.setShare()` reverts normally, `_updatePosition()` suppresses the error and still changes the core staking position. This can leave the external extension's balance/share view permanently out of sync with the staking contract.",
    "impact": "Any downstream system that relies on the extension for rewards, voting power, accounting, or withdrawal rights can over-credit users who already withdrew, under-credit fresh depositors, or lock users out because the external ledger no longer matches `positions`.",
    "paths": [
      "Owner sets an extension that rejects certain accounts or states",
      "A user's `deposit()` or `withdraw()` triggers a caught revert in `setShare()`",
      "The staking contract still updates `positions`, while the extension does not"
    ]
  },
  {
    "id": "F-008",
    "severity": "Low",
    "confidence": "high",
    "title": "Maturity checks are inconsistent, so rewards appear claimable one second before withdrawals actually unlock",
    "locations": [
      "onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:112",
      "onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:183",
      "onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol:233"
    ],
    "claim": "`withdraw()` and `_decreasePosition()` require `block.timestamp > depositTime + period`, while `_calculateRewards()` treats deposits as matured at `block.timestamp >= depositTime + period`.",
    "impact": "At the exact maturity timestamp, frontends or automation that rely on `getPendingRewards()` can believe funds are claimable even though `withdraw()` still reverts. This creates brittle integrations and avoidable failed transactions.",
    "paths": [
      "At `depositTime + period`, `getPendingRewards()` returns a positive value",
      "A same-block `withdraw()` still fails the stricter `>` maturity check"
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
