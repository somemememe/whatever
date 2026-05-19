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
    "title": "Zero-amount withdrawals can permanently disable emergency exits for an entire token",
    "locations": [
      "Staking.sol:363",
      "Staking.sol:385",
      "Staking.sol:487"
    ],
    "claim": "`withdraw` never requires `amount > 0`, but it always updates `lastWithdrawEpochId[tokenAddress]` to the current epoch. Any user with an existing checkpoint history for a token can keep calling `withdraw(token, 0)` once per epoch and continuously refresh the global timer that `emergencyWithdraw` uses.",
    "impact": "A single griefer can globally DoS the contract's fallback exit path for a token. If normal withdrawals ever become unavailable for that token, all stakers can remain trapped indefinitely because the 10-epoch emergency window is reset at near-zero cost.",
    "paths": [
      "Attacker makes an initial dust deposit in a non-stable token to create checkpoints.",
      "Attacker later calls `withdraw(token, 0)` once per epoch.",
      "`lastWithdrawEpochId[token]` is always recent, so `emergencyWithdraw(token)` keeps reverting for every user."
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
    "title": "Emergency withdrawals let users recover principal while remaining counted in epoch accounting",
    "locations": [
      "Staking.sol:61",
      "Staking.sol:385",
      "Staking.sol:487",
      "Staking.sol:495",
      "Staking.sol:508",
      "Staking.sol:558"
    ],
    "claim": "`emergencyWithdraw` is gated only by the token's global `lastWithdrawEpochId`, not by any failed withdrawal attempt from the caller, and that value defaults to zero. After 10 epochs of token-wide withdrawal inactivity, a user can call `emergencyWithdraw` even when the system is otherwise healthy. The function then only zeroes `balances[msg.sender][tokenAddress]` and transfers tokens out; it never updates `balanceCheckpoints` or `poolSize`, so `getEpochUserBalance` and later epoch snapshots can continue to treat the user as staked.",
    "impact": "Users can pull out principal and still retain reward or voting weight in the staking snapshots, leading to reward theft, denominator distortion, and persistent accounting corruption for the pool. Because the gate is based on global token inactivity, this is reachable during ordinary operation for quiet pools, not only during genuine emergencies.",
    "paths": [
      "User stakes a non-stable token and accumulates normal checkpoints.",
      "If that token has not had a successful withdrawal for 10 epochs, the user calls `emergencyWithdraw(token)` and receives their full principal.",
      "Subsequent `getEpochUserBalance(user, token, epoch)` calls still return the stale checkpointed balance, and later pool snapshots can inherit the stale size."
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
    "title": "Historical pool sizes are retroactively mutable for uninitialized epochs",
    "locations": [
      "Staking.sol:466",
      "Staking.sol:558",
      "Staking.sol:572",
      "Staking.sol:579"
    ],
    "claim": "`getEpochPoolSize` is documented as returning the amount locked during a specific epoch, but if that epoch was never initialized it falls back to the contract's current token holdings (`stableCoinBalances` for stablecoins or `token.balanceOf(address(this))` for other tokens). As a result, skipped epochs do not have immutable historical values and can report whatever the contract balance is at query time.",
    "impact": "Any reward or accounting logic that queries past epochs without first forcing sequential initialization can read a rewritten denominator instead of the real pool size that existed in that epoch. This can misprice rewards and historical stake calculations for idle periods.",
    "paths": [
      "Epoch `N` passes without anyone initializing that token's pool size for the epoch.",
      "Later deposits, withdrawals, emergency withdrawals, or direct token transfers change the contract's present balance.",
      "A call to `getEpochPoolSize(token, N)` now returns the new balance rather than the true epoch-`N` pool size."
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "Arbitrary-token deposits credit the requested amount even when fewer or no tokens are received",
    "locations": [
      "Staking.sol:117",
      "Staking.sol:125",
      "Staking.sol:129",
      "Staking.sol:136"
    ],
    "claim": "For non-stable assets, `deposit` accepts any `tokenAddress`, performs a raw `transferFrom`, ignores its boolean return value, and then credits `balances[msg.sender][tokenAddress] += amount` plus checkpoint state using the user-supplied `amount`. The code never measures the actual amount received, so fee-on-transfer tokens and malicious ERC-20s that under-deliver or simply return `false` can mint unbacked stake.",
    "impact": "Attackers can create undercollateralized positions, farm rewards with less capital than recorded, and potentially withdraw honest users' later deposits of the same token. The pool's internal stake accounting can exceed the assets actually held by the contract.",
    "paths": [
      "Attacker chooses a non-stable ERC-20 that charges transfer fees or maliciously returns `false`/under-delivers.",
      "`deposit` records the full requested `amount` as stake even though the contract receives less or nothing.",
      "The attacker later uses the inflated balance for rewards or withdraws against liquidity supplied by honest users of the same token."
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Ignored Compound error codes can leave stablecoin accounting in a silently failed state",
    "locations": [
      "Staking.sol:259",
      "Staking.sol:262",
      "Staking.sol:265",
      "Staking.sol:321",
      "Staking.sol:340"
    ],
    "claim": "Compound's `mint`, `redeem`, and `redeemUnderlying` return numeric error codes, but this contract ignores those values everywhere. Stablecoin deposits update internal balances before proving that `mint` succeeded, and withdrawals/interests paths assume redemptions succeeded as long as the call itself did not revert.",
    "impact": "If Compound returns a non-zero error code, the transaction can still succeed while the protocol's assumptions about where funds reside are wrong. A failed `mint` can leave stablecoins sitting idle in the contract while the pool believes the Compound step succeeded, and failed redemptions can cause temporary withdrawal DoS or cause unrelated idle funds to be used to satisfy withdrawals. This also creates a risk that a failed `mint` leaves a non-zero cToken allowance behind, causing later `safeApprove` calls for that stablecoin to revert and freezing new deposits.",
    "paths": [
      "A stablecoin deposit transfers tokens into the contract and increments `stableCoinBalances`, then calls `CTokenInterface(cToken).mint(amount)`.",
      "Compound returns a non-zero error code instead of reverting, but the staking transaction still succeeds because the return value is ignored.",
      "The pool continues in a partially failed state: assets may remain idle, later redemptions can misbehave, and future deposits can be blocked if the stale allowance is still non-zero."
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
    "id": "F-006",
    "severity": "Medium",
    "confidence": "high",
    "title": "Dormant pools become non-withdrawable until every skipped epoch is manually backfilled",
    "locations": [
      "Staking.sol:142",
      "Staking.sol:387",
      "Staking.sol:466",
      "Staking.sol:477"
    ],
    "claim": "Both `deposit` and `withdraw` try to initialize only the current epoch, but `manualEpochInit` reverts unless `epochId - 1` is already initialized. After a pool sits idle for multiple epochs, the next user action reverts until someone initializes every missing epoch one-by-one.",
    "impact": "A user can be unable to withdraw or restake after a long inactivity period, creating a real lockup/liveness failure for dormant pools. The longer the pool stays inactive, the more manual transactions are required before funds can move again.",
    "paths": [
      "User deposits token T in epoch N, creating snapshots for epochs N and N+1.",
      "No one interacts with token T for many epochs.",
      "A later `withdraw(T, amount)` or `deposit(T, amount, referrer)` hits `manualEpochInit(T, currentEpoch)`.",
      "Initialization reverts because `poolSize[T][currentEpoch - 1]` was never initialized, so the user must first backfill every skipped epoch sequentially."
    ]
  },
  {
    "id": "F-007",
    "severity": "High",
    "confidence": "medium",
    "title": "Stablecoin principal has no emergency escape hatch if Compound redemptions stop working",
    "locations": [
      "Staking.sol:119",
      "Staking.sol:127",
      "Staking.sol:370",
      "Staking.sol:489"
    ],
    "claim": "All stablecoin deposits are forwarded into Compound, but `emergencyWithdraw` explicitly rejects stablecoins. That leaves `withdraw` as the only exit path, and it depends entirely on successful Compound redemption.",
    "impact": "If Compound redemptions are paused, cash is unavailable, or the cToken integration becomes unusable, every USDC/USDT/DAI staker can be trapped with no on-contract recovery path for principal.",
    "paths": [
      "User deposits USDC/USDT/DAI, and the contract mints the corresponding cToken.",
      "Compound later cannot satisfy `redeemUnderlying` for that market.",
      "User calls `withdraw`, which cannot source principal without Compound redemption.",
      "User cannot fall back to `emergencyWithdraw` because stablecoins are hard-blocked."
    ]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Withdraw and emergency-withdraw can silently burn a user's claim when token transfers return false",
    "locations": [
      "Staking.sol:368",
      "Staking.sol:374",
      "Staking.sol:376",
      "Staking.sol:379",
      "Staking.sol:495",
      "Staking.sol:498"
    ],
    "claim": "Outgoing token transfers in `withdraw` and `emergencyWithdraw` ignore the ERC-20 return value for all non-USDT paths. If a token returns `false` instead of reverting, the function still completes after reducing or zeroing the user's recorded balance.",
    "impact": "Users can lose their staking position without receiving tokens back. Because the contract accepts arbitrary non-stable tokens, a faulty or malicious ERC-20 can permanently desynchronize accounting from actual payouts.",
    "paths": [
      "User stakes a token whose `transfer` returns `false` on payout.",
      "`withdraw` or `emergencyWithdraw` first decreases `balances[msg.sender][token]`.",
      "The token transfer returns `false`, but the contract does not check it and does not revert.",
      "The transaction succeeds while the user receives no tokens and their claim is already reduced or erased."
    ]
  },
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "low",
    "title": "Anyone can force team interest withdrawals ahead of users during Compound liquidity stress",
    "locations": [
      "Staking.sol:306",
      "Staking.sol:318",
      "Staking.sol:321",
      "Staking.sol:332",
      "Staking.sol:340"
    ],
    "claim": "`getInterestFromCompound` and `getInterest` are permissionless, so any third party can redeem available Compound liquidity and route accrued yield to `TEAM_ADDRESS` before pending user principal withdrawals execute.",
    "impact": "In a low-liquidity Compound market, public callers can prioritize team payouts over staker exits, worsening withdrawal failures and making stablecoin lockups more likely at the exact moment users need liquidity most.",
    "paths": [
      "Compound market liquidity becomes constrained but still has some redeemable cash.",
      "A user submits a stablecoin `withdraw`.",
      "A third party front-runs with `getInterestFromCompound(token)` or `getInterest(token)`.",
      "The function redeems underlying and transfers the available interest to `TEAM_ADDRESS`, leaving less liquidity for the user's principal withdrawal."
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
