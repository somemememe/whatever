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
    "title": "Any dust withdrawal can indefinitely block emergency exits for an entire token",
    "locations": [
      "Staking.sol:61",
      "Staking.sol:363",
      "Staking.sol:385",
      "Staking.sol:490"
    ],
    "claim": "`lastWithdrawEpochId` is tracked globally per token, not per user or per failed-withdrawal state, and every successful `withdraw()` refreshes it to the current epoch. Because `withdraw()` only checks `balances[msg.sender][token] >= amount`, an attacker can keep resetting the timer with either `withdraw(token, 0)` or repeated tiny positive withdrawals after maintaining a dust position.",
    "impact": "A single griefer can permissionlessly suppress the contract's fallback exit path for a token. If ordinary withdrawals become unavailable or only partially available for most users, honest stakers can remain trapped indefinitely because the 10-epoch emergency window is reset at negligible cost.",
    "paths": [
      "Attacker creates or keeps a dust stake in a non-stable token.",
      "Before 10 epochs elapse, the attacker calls `withdraw(token, 0)` or withdraws a tiny positive amount.",
      "`lastWithdrawEpochId[token]` becomes recent again, so `emergencyWithdraw(token)` keeps reverting for every other user."
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
    "confidence": "high",
    "title": "Ignored Compound error codes can silently corrupt stablecoin state, brick future deposits, and expose principal to team sweeps",
    "locations": [
      "Staking.sol:259",
      "Staking.sol:261",
      "Staking.sol:262",
      "Staking.sol:265",
      "Staking.sol:314",
      "Staking.sol:318",
      "Staking.sol:321",
      "Staking.sol:340",
      "Staking.sol:355",
      "Staking.sol:356",
      "Staking.sol:363",
      "Staking.sol:371",
      "Staking.sol:372",
      "SafeERC20.sol:60",
      "SafeERC20.sol:65"
    ],
    "claim": "All Compound interactions ignore the numeric return codes from `mint`, `redeem`, and `redeemUnderlying`. Stablecoin deposits update `stableCoinBalances` and user balances before proving that `mint` succeeded, withdrawals decrement both `balances` and `stableCoinBalances` before proving that `redeemUnderlying` succeeded, and interest sweeps assume redemptions succeeded as long as the external call did not revert. If `redeemUnderlying()` fails without reverting while the staking contract already holds enough idle underlying tokens, the user is still paid, `stableCoinBalances` drops, and the unredeemed principal remains inside Compound; later `getInterestFromCompound()` / `getInterest()` then compare actual Compound backing against the reduced `stableCoinBalances` and can misclassify that stranded principal as team-owned interest. A failed `mint` can also leave a non-zero cToken allowance behind because `safeApprove` set it first and there is no path that resets it back to zero.",
    "impact": "A non-reverting Compound-side failure can leave the pool in a silently inconsistent state: principal may sit idle in the staking contract while users are recorded as invested, principal may remain in Compound after users are treated as withdrawn, unrelated idle balances may be consumed to satisfy withdrawals, permissionless interest sweeps can later transfer part of backed user principal to `TEAM_ADDRESS`, and one failed `mint` can permanently DoS new deposits or the `getInterest()` re-mint path for that stablecoin because future `safeApprove` calls revert on the leftover allowance.",
    "paths": [
      "A stablecoin `deposit()` or `getInterest()` sets cToken allowance via `safeApprove()` and then calls `mint()`.",
      "`mint()` returns a non-zero error code instead of reverting, so the transaction succeeds and the allowance may remain non-zero while internal accounting already assumes the funds were invested.",
      "Or, a user's stablecoin `withdraw()` decrements `stableCoinBalances` and calls `redeemUnderlying(amount)`, which returns a non-zero error while the contract already has enough idle underlying to pay the user anyway.",
      "Later `getInterestFromCompound(token)` or `getInterest(token)` treats the unreduced Compound backing minus the reduced `stableCoinBalances` as withdrawable interest and forwards it to `TEAM_ADDRESS`.",
      "Future deposits or re-mint attempts can also hit `safeApprove()` again and revert because the old allowance was never reset to zero."
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
    "title": "Skipped epochs and the hardcoded 2021 epoch start can brick dormant or never-before-used pools",
    "locations": [
      "Staking.sol:90",
      "Staking.sol:91",
      "Staking.sol:142",
      "Staking.sol:145",
      "Staking.sol:387",
      "Staking.sol:466",
      "Staking.sol:477"
    ],
    "claim": "The constructor permanently hardcodes `epoch1Start = 1624230000` (June 21, 2021), while `deposit` and `withdraw` only attempt to initialize the current epoch. `manualEpochInit` then reverts unless `epochId - 1` is already initialized. Once `currentEpoch` has advanced beyond a pool's last initialized epoch—either because a pool sat idle for several epochs or because a token pool is first used long after June 2021—the next `deposit` or `withdraw` hits `manualEpochInit(..., currentEpoch)` and reverts until every missing epoch is backfilled sequentially.",
    "impact": "Dormant pools lose liveness, and fresh deployments, migrations, or late-added token pools can start effectively unusable. Users may face practical lockup until someone spends one transaction per missing epoch to restore the pool's initialization chain.",
    "paths": [
      "The contract is deployed after June 21, 2021, or a token is first used only after many epochs have already elapsed.",
      "A user's first `deposit(token, amount, referrer)` or later `withdraw(token, amount)` calls `manualEpochInit(token, currentEpoch)`.",
      "`manualEpochInit` requires `epochId - 1` to already be initialized and reverts because the skipped epochs were never backfilled.",
      "The pool cannot be used again until someone initializes every missing epoch one by one."
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
  },
  {
    "id": "F-010",
    "severity": "Medium",
    "confidence": "high",
    "title": "Non-stable pool snapshots trust raw contract balances instead of tracked user stake",
    "locations": [
      "Staking.sol:149",
      "Staking.sol:153",
      "Staking.sol:394",
      "Staking.sol:398",
      "Staking.sol:558",
      "Staking.sol:579"
    ],
    "claim": "For non-stable assets, both `deposit` and `withdraw` set `poolSize[token][currentEpoch + 1]` from `IERC20(token).balanceOf(address(this))`, and `getEpochPoolSize` also falls back to that raw balance for uninitialized epochs. Because pool sizing is derived from the token's live contract balance instead of the sum of tracked user balances, unsolicited transfers, rebases, reflection mechanics, or a malicious `balanceOf` implementation can change pool sizes without changing `balances` or user checkpoints.",
    "impact": "Epoch denominators can diverge from the actual staked positions the contract tracks, distorting any reward or accounting logic that relies on pool size. Negative balance drift can also leave the contract undercollateralized relative to recorded user claims, while inflated balances can dilute or manipulate rewards.",
    "paths": [
      "An attacker or the token itself changes the staking contract's token balance without going through `deposit` or `withdraw`.",
      "A later interaction stores that raw balance into `poolSize[token][currentEpoch + 1]`, or `getEpochPoolSize` returns the raw balance for an uninitialized epoch.",
      "Pool-size snapshots no longer match the recorded user stakes, corrupting downstream accounting."
    ],
    "round": 3,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-011",
    "severity": "Medium",
    "confidence": "low",
    "title": "Permissionless interest sweeps can front-run stablecoin withdrawals and worsen liquidity shortfalls",
    "locations": [
      "Staking.sol:306",
      "Staking.sol:321",
      "Staking.sol:332",
      "Staking.sol:340",
      "Staking.sol:363",
      "Staking.sol:372"
    ],
    "claim": "`getInterestFromCompound` and `getInterest` are permissionless even though the latter is only commented as being recommended after users have exited. Any third party can redeem accrued underlying from Compound and forward the extracted amount to `TEAM_ADDRESS` before users withdraw. When Compound cash is tight, this can consume redeemable liquidity that would otherwise remain available for user withdrawals.",
    "impact": "An outsider can grief stablecoin stakers by making borderline-liquid pools fail withdrawals sooner or remain illiquid longer, amplifying the contract's existing lack of any fallback exit for stablecoin positions.",
    "paths": [
      "Compound has only limited spare cash above the pool's tracked principal.",
      "A third party front-runs a user's stablecoin withdrawal with `getInterestFromCompound(token)` or `getInterest(token)`.",
      "The contract redeems underlying and forwards the extracted amount to `TEAM_ADDRESS`.",
      "The user's later `withdraw` faces a smaller redeemable buffer and can no longer redeem cleanly from Compound."
    ],
    "round": 3,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-012",
    "severity": "Medium",
    "confidence": "high",
    "title": "Anyone can overwrite an already-initialized epoch-0 pool snapshot",
    "locations": [
      "Staking.sol:466",
      "Staking.sol:472",
      "Staking.sol:479"
    ],
    "claim": "`manualEpochInit()` special-cases `epochId == 0` by unconditionally writing `poolSize[token][0] = 0` and `set = true`, without checking whether epoch 0 was already initialized with a real nonzero size. Any caller can therefore reset an existing epoch-0 snapshot after pre-start deposits have populated it.",
    "impact": "Pre-start stakers can be erased from the baseline pool accounting used to seed later epochs. If epoch 1 and subsequent epochs are still initialized lazily, an attacker can propagate the forged zero snapshot forward and distort or deny the initial reward allocation for legitimate stakers.",
    "paths": [
      "Users deposit before epoch 1 starts, so epoch 0 is initialized and `poolSize[token][0]` becomes nonzero.",
      "An attacker later calls `manualEpochInit([token], 0)`, which overwrites that existing snapshot with zero.",
      "Before any real interaction repairs the chain, the attacker or anyone else initializes later epochs from the forged predecessor, propagating the zero baseline into live reward epochs."
    ],
    "round": 5,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-013",
    "severity": "Medium",
    "confidence": "high",
    "title": "Permissionless `getInterest()` can confiscate unrelated stablecoins held by the contract",
    "locations": [
      "Staking.sol:332",
      "Staking.sol:340",
      "Staking.sol:342",
      "Staking.sol:344",
      "Staking.sol:349"
    ],
    "claim": "`getInterest()` redeems all cTokens for a stablecoin and then treats every on-contract token balance above `stableCoinBalances[token]` as team-owned interest. The function does not distinguish real Compound yield from unrelated stablecoins already sitting on the contract, such as accidental direct transfers or principal stranded on the contract by earlier accounting mismatches, as long as some cToken balance exists to satisfy the function's entry check.",
    "impact": "Stablecoins that do not belong to the team can be irreversibly transferred to `TEAM_ADDRESS` by any caller. This turns stray transfers or previously stranded principal into permanent loss of funds for their rightful owner.",
    "paths": [
      "Stablecoins end up on the staking contract without increasing `stableCoinBalances[token]`, while the contract still holds some corresponding cTokens.",
      "Any account calls `getInterest(token)`, which redeems all cTokens for that market.",
      "The function computes `interest = IERC20(token).balanceOf(address(this)) - stableCoinBalances[token]` and transfers that full difference to `TEAM_ADDRESS`, including unrelated funds."
    ],
    "round": 5,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-014",
    "severity": "Medium",
    "confidence": "high",
    "title": "Unexpected cToken transfers are misclassified as protocol yield and can be swept to the team",
    "locations": [
      "Staking.sol:286",
      "Staking.sol:314",
      "Staking.sol:318",
      "Staking.sol:336",
      "Staking.sol:344"
    ],
    "claim": "The interest-handling logic treats the contract's entire Compound position as if it were backed by tracked user principal. If anyone transfers `cUSDC`, `cUSDT`, or `cDAI` directly to the staking contract, `balanceOfUnderlying(address(this))` and later redeemed underlying increase while `stableCoinBalances[token]` does not, so the surplus is classified as withdrawable 'interest' and can be redeemed and forwarded to `TEAM_ADDRESS`.",
    "impact": "Accidentally or intentionally transferred cTokens are confiscatable. Any caller can trigger `getInterestFromCompound()` to redeem most of their underlying value to the team, and `getInterest()` can ultimately sweep the remainder as well. This broadens the asset-confiscation surface beyond raw stablecoins already sitting in the contract wallet.",
    "paths": [
      "A third party transfers `cUSDC`, `cUSDT`, or `cDAI` directly to the staking contract.",
      "`stableCoinBalances[token]` stays unchanged, but the contract's Compound position and its underlying value rise.",
      "Any caller invokes `getInterestFromCompound(token)` or `getInterest(token)`.",
      "The donated cToken position is treated as excess yield and its underlying is sent to `TEAM_ADDRESS`."
    ],
    "round": 6,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-015",
    "severity": "High",
    "confidence": "high",
    "title": "Withdrawal checkpoint math lets users keep late deposits with inflated same-epoch weight",
    "locations": [
      "Staking.sol:186",
      "Staking.sol:192",
      "Staking.sol:430",
      "Staking.sol:443",
      "Staking.sol:448"
    ],
    "claim": "The checkpoint model collapses all same-epoch deposits into one `newDeposits` bucket with a single averaged `multiplier`, and `withdraw()` never tracks which tranche is actually being removed. If a user makes multiple deposits in the same epoch, withdrawing an earlier high-weight tranche only reduces `newDeposits` while preserving the averaged multiplier on the remainder. If a user starts the epoch with carried balance and then deposits late, withdrawing at least `newDeposits` moves the remainder into `startBalance` with `BASE_MULTIPLIER`, which can leave only the late deposit recorded as full-epoch stake.",
    "impact": "A user can overstate their effective balance for the current epoch and capture more than their fair share of epoch rewards at the expense of honest stakers. Because this only requires timing deposits and withdrawals around the epoch boundary, it is a repeatable economic-extraction vector rather than a one-off accounting glitch.",
    "paths": [
      "Deposit a large amount early in an epoch, deposit a smaller amount near the epoch end, then withdraw the early deposit before rollover; the remaining late deposit keeps the blended multiplier instead of its true near-zero weight.",
      "Begin the epoch with an existing carried balance, add a large deposit near the epoch end, then withdraw an amount equal to or larger than `newDeposits`; the code converts the remainder to `startBalance` with `BASE_MULTIPLIER`, so only the late deposit can remain while being credited as full-epoch stake."
    ],
    "round": 8,
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
    "id": "F-016",
    "severity": "High",
    "confidence": "high",
    "title": "Former stakers can block emergency exits forever with zero-amount withdrawals",
    "locations": [
      "Staking.sol:363",
      "Staking.sol:385",
      "Staking.sol:402",
      "Staking.sol:487"
    ],
    "claim": "`withdraw()` never requires `amount > 0`, but it still refreshes the global `lastWithdrawEpochId[tokenAddress]`. Because old checkpoints remain after a user fully exits, any address that has ever staked a non-stable token can keep calling `withdraw(token, 0)` once per epoch and continuously reset the 10-epoch emergency-withdraw timer without holding any stake.",
    "impact": "A single historical participant can permanently deny `emergencyWithdraw()` for an entire non-stable pool at near-zero cost, even after fully withdrawing their own position.",
    "paths": [
      "User stakes a non-stable token once, creating checkpoints.",
      "User later withdraws their full balance, leaving `balances[user][token] == 0` but preserving checkpoints.",
      "Each epoch, the user calls `withdraw(token, 0)`; the call succeeds, updates `lastWithdrawEpochId[token]`, and keeps `emergencyWithdraw(token)` unavailable for everyone else."
    ]
  },
  {
    "id": "F-017",
    "severity": "High",
    "confidence": "high",
    "title": "Arbitrary-token exits burn full claims even when the user receives fewer tokens",
    "locations": [
      "Staking.sol:368",
      "Staking.sol:378",
      "Staking.sol:379",
      "Staking.sol:495",
      "Staking.sol:498"
    ],
    "claim": "For non-stable tokens, both `withdraw()` and `emergencyWithdraw()` reduce the user's recorded stake by the requested `amount` and then call `token.transfer(...)` without verifying how many tokens were actually delivered. Any fee-on-transfer, deflationary, or malicious token that returns `true` while transferring less than requested can short-pay the user while still burning their full claim.",
    "impact": "Users can permanently lose part or all of their principal on exit. A malicious token can behave normally on deposit, then skim or suppress outbound transfers so withdrawals appear successful while users receive only a fraction of what their staking balance says they own.",
    "paths": [
      "Attacker or integrator uses a non-stable token whose `transferFrom` into staking succeeds normally, but whose outbound `transfer` taxes, burns, or short-sends tokens while still returning `true`.",
      "Victim deposits the token and receives full staking credit.",
      "On `withdraw()` or `emergencyWithdraw()`, the contract deducts the full balance first, but the token delivers less than `amount`, leaving the victim underpaid with no remaining on-contract claim."
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
