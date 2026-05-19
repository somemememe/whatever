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
  },
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
    "claim": "`deposit` and `withdraw` only attempt to initialize the current epoch, but `manualEpochInit` reverts unless `epochId - 1` is already initialized. After a token pool sits idle across multiple epochs, the next `deposit` or `withdraw` hits `manualEpochInit(token, currentEpoch)` and reverts because the immediately preceding epoch was never backfilled.",
    "impact": "Dormant pools lose liveness: users cannot withdraw or restake after a long inactivity period until someone submits one transaction per missing epoch. For long gaps this becomes a practical lockup and can delay exits exactly when a quiet pool becomes active again.",
    "paths": [
      "A user stakes token `T`, which initializes snapshots only through epoch `N+1`.",
      "No one interacts with `T` for several later epochs.",
      "A later `withdraw(T, amount)` or `deposit(T, amount, referrer)` calls `manualEpochInit(..., currentEpoch)`.",
      "`manualEpochInit` reverts on `previous epoch not initialized`, so users must backfill each skipped epoch sequentially before funds can move."
    ],
    "round": 2,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Stablecoin stakers have no on-contract fallback exit if the Compound integration becomes unavailable",
    "locations": [
      "Staking.sol:119",
      "Staking.sol:127",
      "Staking.sol:370",
      "Staking.sol:489"
    ],
    "claim": "Stablecoin deposits are automatically forwarded into Compound, while `emergencyWithdraw` explicitly rejects stablecoins. That leaves `withdraw` as the only principal exit path for USDC/USDT/DAI, and it depends entirely on successful Compound redemption.",
    "impact": "If the Compound market is paused, lacks cash, or otherwise becomes unusable for redemption, stablecoin stakers can be left without any protocol-level escape hatch for principal. This turns an external integration failure into a full lockup for those pools.",
    "paths": [
      "A user deposits USDC, USDT, or DAI, and the contract forwards the funds into the corresponding cToken market.",
      "Compound later cannot redeem the requested underlying, whether because liquidity is unavailable or the market integration is broken.",
      "The user's `withdraw` cannot source principal from anywhere else, and `emergencyWithdraw` is unavailable because stablecoins are hard-blocked."
    ],
    "round": 2,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "high",
    "title": "Withdraw and emergency-withdraw can silently burn a user's claim when token transfers return false",
    "locations": [
      "Staking.sol:368",
      "Staking.sol:374",
      "Staking.sol:376",
      "Staking.sol:379",
      "Staking.sol:495",
      "Staking.sol:498"
    ],
    "claim": "Outgoing token transfers in `withdraw` and `emergencyWithdraw` ignore the ERC-20 return value on every standard-ERC20 path. The functions reduce or erase the user's recorded balance before calling `transfer`, so a token that returns `false` instead of reverting causes the transaction to succeed without paying the user.",
    "impact": "Users can lose some or all of their staking position while receiving no tokens back. Because arbitrary non-stable ERC-20s are accepted, a faulty or malicious token can permanently desynchronize the protocol's accounting from actual payouts and trap value in the contract.",
    "paths": [
      "A user stakes a token whose `transfer` returns `false` on outbound payouts.",
      "The user calls `withdraw` or `emergencyWithdraw`, which first decrements or zeroes `balances[msg.sender][token]`.",
      "The token transfer returns `false`, but the contract does not check it and does not revert.",
      "The transaction succeeds while the user receives no tokens and their claim has already been reduced or erased."
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
    "id": "F-009",
    "severity": "High",
    "confidence": "high",
    "title": "Fee-on-transfer withdrawals burn the full stake even when the user receives less",
    "locations": [
      "Staking.sol:363",
      "Staking.sol:379",
      "Staking.sol:487",
      "Staking.sol:498"
    ],
    "claim": "For non-stable tokens, `withdraw` and `emergencyWithdraw` deduct the full recorded balance before calling `transfer(msg.sender, amount)`, but they never verify how many tokens were actually delivered. Any token that charges an outbound transfer fee or burn can return success while sending less than `amount`, leaving the user short while their entire claim is still cleared.",
    "impact": "Users can permanently lose principal on exit. A malicious or deflationary token can skim or burn part of every withdrawal while the contract still reduces balances and epoch accounting by the full requested amount.",
    "paths": [
      "A user deposits a non-stable token whose transfers burn or tax part of the amount.",
      "The user calls `withdraw` or `emergencyWithdraw`.",
      "The contract reduces the user's internal stake by the full `amount`, but the token only delivers `amount - fee` to the user.",
      "The missing value is permanently lost while the user's claim is already consumed."
    ]
  },
  {
    "id": "F-010",
    "severity": "Medium",
    "confidence": "high",
    "title": "Raw token balances can poison non-stable pool snapshots and make accounting diverge from user stakes",
    "locations": [
      "Staking.sol:149",
      "Staking.sol:153",
      "Staking.sol:394",
      "Staking.sol:398",
      "Staking.sol:558",
      "Staking.sol:579"
    ],
    "claim": "Non-stable pool sizing is derived from `IERC20(token).balanceOf(address(this))` instead of the sum of tracked user balances. Any balance change that happens outside the contract's own bookkeeping—such as direct transfers, rebases, reflection mechanics, or a malicious `balanceOf` implementation—can change pool sizes without changing user checkpoints or `balances`.",
    "impact": "Reward calculations that rely on epoch pool sizes can be diluted or manipulated, and negative balance drift can leave the contract undercollateralized versus recorded user claims. The contract's historical and future pool views stop matching the actual staked positions it tracks.",
    "paths": [
      "An attacker or the token itself changes the staking contract's balance without going through `deposit`/`withdraw`.",
      "A later action stores that raw contract balance into `poolSize[currentEpoch + 1]`, or `getEpochPoolSize` returns the raw balance for an uninitialized epoch.",
      "Pool-size snapshots diverge from user balances/checkpoints, corrupting downstream accounting."
    ]
  },
  {
    "id": "F-011",
    "severity": "Medium",
    "confidence": "low",
    "title": "Anyone can front-run stablecoin withdrawals by redeeming Compound interest to the team first",
    "locations": [
      "Staking.sol:306",
      "Staking.sol:321",
      "Staking.sol:332",
      "Staking.sol:340",
      "Staking.sol:363",
      "Staking.sol:372"
    ],
    "claim": "`getInterestFromCompound` and `getInterest` are permissionless, so any third party can redeem underlying from Compound and forward the extracted interest to `TEAM_ADDRESS` before users withdraw. During periods of limited Compound cash, this lets outsiders prioritize team interest extraction over user redemptions.",
    "impact": "A withdrawal that would otherwise have succeeded can be pushed into failure or prolonged illiquidity if a third party drains the remaining redeemable cash as 'interest' first. Stablecoin users then inherit the protocol's existing lack of a reliable fallback exit.",
    "paths": [
      "Compound has enough cash for a pending user withdrawal only if accrued interest remains untouched.",
      "A third party front-runs the user with `getInterestFromCompound` or `getInterest`.",
      "The contract redeems underlying and transfers the extracted amount to `TEAM_ADDRESS`.",
      "The user's later `withdraw` hits a reduced-liquidity Compound position and can no longer redeem cleanly."
    ]
  },
  {
    "id": "F-012",
    "severity": "Medium",
    "confidence": "high",
    "title": "The hardcoded June 2021 epoch start can brick fresh deployments and never-before-used pools",
    "locations": [
      "Staking.sol:90",
      "Staking.sol:91",
      "Staking.sol:142",
      "Staking.sol:145",
      "Staking.sol:466",
      "Staking.sol:477"
    ],
    "claim": "The constructor permanently hardcodes `epoch1Start = 1624230000` (June 21, 2021). If the contract is deployed, migrated, or a new token pool is first used after that date, `getCurrentEpoch()` is already far in the future and the first normal `deposit` tries to initialize only the current epoch, which reverts unless every prior epoch has already been backfilled one by one.",
    "impact": "A fresh deployment or newly introduced pool can start effectively unusable, requiring a large number of manual epoch-initialization transactions before any standard deposit flow works. This creates a protocol-level liveness failure for migrations and late-added pools.",
    "paths": [
      "The contract is deployed after June 21, 2021, or a token is first used long after epoch 0.",
      "The first `deposit` for that token reaches `manualEpochInit(token, currentEpoch)`.",
      "`manualEpochInit` requires `epochId - 1` to already be initialized and reverts.",
      "The pool cannot be bootstrapped without backfilling all missed epochs manually."
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
