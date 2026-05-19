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
    "title": "Unchecked ERC20 transfer return values allow phantom deposits and silent failed withdrawals",
    "locations": [
      "Staking.sol:123",
      "Staking.sol:125",
      "Staking.sol:129",
      "Staking.sol:374",
      "Staking.sol:376",
      "Staking.sol:379",
      "Staking.sol:498"
    ],
    "claim": "`deposit`, `withdraw`, and `emergencyWithdraw` call `transferFrom`/`transfer` directly and ignore the returned boolean. For any accepted token that returns `false` instead of reverting, the contract still updates `balances`, checkpoints, pool sizes, and stable-coin accounting as if tokens moved successfully.",
    "impact": "An attacker can create or use a token whose `transferFrom` silently fails for them, obtain stake credit without funding the pool, and later withdraw real liquidity deposited by other users of the same token. Failed outbound transfers can also leave users debited without actually receiving tokens.",
    "paths": [
      "Use a non-stable token that returns `false` on `transferFrom` for the attacker but still allows normal transfers for other users.",
      "Call `deposit(token, amount, referrer)`; the contract records `amount` as staked even though it received nothing.",
      "After honest users deposit the same token, call `withdraw` to receive real tokens from the contract while your original deposit was never funded."
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
    "title": "Deposits credit the requested amount instead of the tokens actually received",
    "locations": [
      "Staking.sol:120",
      "Staking.sol:127",
      "Staking.sol:136",
      "Staking.sol:149",
      "Staking.sol:151",
      "Staking.sol:153",
      "Staking.sol:166",
      "Staking.sol:181",
      "Staking.sol:194",
      "Staking.sol:214",
      "Staking.sol:368",
      "Staking.sol:371",
      "Staking.sol:394",
      "Staking.sol:396",
      "Staking.sol:398"
    ],
    "claim": "`deposit` increases `stableCoinBalances`, user `balances`, checkpoints, and epoch pool accounting by the caller-supplied `amount` without measuring how many tokens the contract actually received. Fee-on-transfer, deflationary, rebasing, or hook-based tokens therefore create over-credited positions.",
    "impact": "A user can deposit a taxed or deflationary token, receive credit for more tokens than arrived, and later over-withdraw from that token pool once enough honest liquidity exists. The mismatch also corrupts epoch snapshots and reward-weight calculations.",
    "paths": [
      "Use a non-stable token that transfers only `amount - fee` to the staking contract.",
      "Call `deposit(token, amount, referrer)`; internal accounting and checkpoints increase by `amount`, not by the net tokens received.",
      "Later withdraw the full recorded balance, consuming liquidity supplied by later depositors."
    ],
    "round": 1,
    "source_agents": [
      "codex"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Emergency withdrawal lets users recover principal while retaining stale epoch stake, and untouched pools are immediately eligible",
    "locations": [
      "Staking.sol:59",
      "Staking.sol:487",
      "Staking.sol:490",
      "Staking.sol:495",
      "Staking.sol:498",
      "Staking.sol:508",
      "Staking.sol:520",
      "Staking.sol:558",
      "Staking.sol:562"
    ],
    "claim": "`emergencyWithdraw` only zeroes `balances[msg.sender][token]` and transfers tokens out; it does not update `balanceCheckpoints`, initialized `poolSize` snapshots, or any other epoch state consumed by `getEpochUserBalance` and `getEpochPoolSize`. Worse, `lastWithdrawEpochId[token]` defaults to `0`, and `getCurrentEpoch()` is already far greater than 10 because epochs started in June 2021, so any non-stable token pool with no prior successful normal withdrawal is immediately eligible for emergency exit.",
    "impact": "A user can deposit into a fresh or untouched non-stable pool, immediately recover their principal through `emergencyWithdraw`, and still appear staked in epoch-based snapshot logic. Any rewards, voting weight, or accounting that relies on these getters can be stolen or distorted while the user no longer has funds at risk.",
    "paths": [
      "Use a non-stable token pool that has never had a successful normal `withdraw` recorded.",
      "Call `deposit(token, amount, referrer)` to create checkpoints and initialize epoch snapshots.",
      "Immediately call `emergencyWithdraw(token)`; the tokens are returned, but `getEpochUserBalance` and initialized pool snapshots still reflect the old stake."
    ],
    "round": 1,
    "source_agents": [
      "codex",
      "merge-review"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "Any small withdrawal can indefinitely grief the emergency-exit timer for an entire token pool",
    "locations": [
      "Staking.sol:59",
      "Staking.sol:385",
      "Staking.sol:487",
      "Staking.sol:490"
    ],
    "claim": "The emergency-exit gate is tracked in the single global variable `lastWithdrawEpochId[token]`. Every successful normal withdrawal, no matter which user performed it or how small the amount was, resets the timer for all users in that token pool.",
    "impact": "An attacker with a dust position can keep `emergencyWithdraw` unavailable indefinitely by periodically withdrawing tiny amounts. If the pool later becomes dysfunctional or ordinary withdrawals stop working, all other stakers can be trapped without access to the advertised rescue path.",
    "paths": [
      "Acquire a minimal stake in a non-stable token pool.",
      "Call `withdraw(token, dust)` at least once every 9 epochs.",
      "All other users fail `emergencyWithdraw` because `getCurrentEpoch() - lastWithdrawEpochId[token]` never reaches 10."
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
    "title": "Dormant pools become unusable until every missed epoch is initialized one transaction at a time",
    "locations": [
      "Staking.sol:142",
      "Staking.sol:145",
      "Staking.sol:387",
      "Staking.sol:390",
      "Staking.sol:466",
      "Staking.sol:477",
      "Staking.sol:479"
    ],
    "claim": "When a pool is inactive for more than one epoch beyond the auto-initialized `current + 1` snapshot, both `deposit` and `withdraw` try to initialize only the current epoch. `manualEpochInit` then reverts because it requires `epochId - 1` to already be initialized, so skipped epochs must be backfilled strictly one by one.",
    "impact": "After long inactivity, normal deposits and withdrawals revert until someone submits a separate `manualEpochInit` transaction for every missed epoch. This creates a practical denial of service and can leave a dormant pool unusable until an arbitrarily large catch-up sequence is executed.",
    "paths": [
      "Let a token pool sit idle for many epochs after its last activity.",
      "Attempt `deposit` or `withdraw` in the current epoch; the internal `manualEpochInit(currentEpoch)` call reverts because `currentEpoch - 1` was never initialized.",
      "Users must send one catch-up initialization transaction per missing epoch before normal operations resume."
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
    "title": "Ignored Compound error codes can desynchronize stablecoin accounting from real liquidity",
    "locations": [
      "Staking.sol:262",
      "Staking.sol:267",
      "Staking.sol:321",
      "Staking.sol:340",
      "Staking.sol:356"
    ],
    "claim": "Compound's `mint`, `redeemUnderlying`, and `redeem` return non-zero error codes on failure instead of reverting, but the contract ignores those return values everywhere. The staking logic therefore assumes stablecoins moved into or out of Compound even when Compound explicitly reported failure.",
    "impact": "Paused markets, insufficient cash, or other Compound-side failures can leave `stableCoinBalances`, on-hand token balances, and cToken positions out of sync. Withdrawals can proceed after local balances are debited even though liquidity was never redeemed, interest extraction can malfunction, and later users can face failed or unfair withdrawals.",
    "paths": [
      "A stablecoin withdrawal calls `_redeemFromCompound(amount)`, but Compound returns a non-zero error code because redemption cannot be satisfied.",
      "The function continues as if redemption succeeded and attempts to transfer tokens to the user anyway.",
      "Accounting has already been reduced locally, so the contract can enter an inconsistent state and subsequent withdrawals or interest operations can fail."
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
    "id": "F-007",
    "severity": "High",
    "confidence": "medium",
    "title": "Anyone can reset epoch 0 to zero and corrupt the first live epoch’s denominator",
    "locations": [
      "Staking.sol:466",
      "Staking.sol:472",
      "Staking.sol:479"
    ],
    "claim": "`manualEpochInit()` treats `epochId == 0` as a blind write and never checks whether epoch 0 was already initialized, so any caller can overwrite the bootstrap pool size with zero after users have already staked.",
    "impact": "If users deposited during epoch 0, an attacker can erase that carried-forward pool size just before epoch 1 is initialized. Epoch 1 then inherits `0` as its starting pool size while users still retain positive epoch-1 balances in their checkpoints, which can break reward accounting or let the first post-bootstrap actor capture a disproportionate share of rewards.",
    "paths": [
      "Honest users deposit before `epoch1Start`, creating non-zero epoch-0 stake.",
      "Attacker calls `manualEpochInit([token], 0)` and resets `poolSize[token][0].size` to zero.",
      "The first epoch-1 initialization copies that zero into `poolSize[token][1]`, omitting all carried stake from the denominator."
    ]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "high",
    "title": "Direct token transfers or rebases permanently poison non-stable pool-size accounting",
    "locations": [
      "Staking.sol:148",
      "Staking.sol:153",
      "Staking.sol:393",
      "Staking.sol:398",
      "Staking.sol:558",
      "Staking.sol:579"
    ],
    "claim": "For non-stable tokens, the contract snapshots pool size from `IERC20(token).balanceOf(address(this))` instead of an internally tracked total, so unsolicited transfers, token donations, or positive rebases inflate pool size without creating any matching user balance or checkpoint.",
    "impact": "Future epoch denominators can exceed the sum of withdrawable user stakes, diluting rewards and permanently trapping the excess tokens inside the contract. This works even with standard ERC20s, because a third party can simply transfer tokens directly to the staking contract without calling `deposit()`.",
    "paths": [
      "An attacker or mistaken sender transfers non-stable tokens directly to the staking contract.",
      "A later `deposit()` or `withdraw()` snapshots `pNextEpoch.size` from the raw on-chain token balance.",
      "Rewards or accounting that rely on `getEpochPoolSize()` now use an inflated denominator that no user can fully withdraw against."
    ]
  },
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Uninitialized historical epochs read mutable current balances instead of fixed snapshots",
    "locations": [
      "Staking.sol:558",
      "Staking.sol:563",
      "Staking.sol:571",
      "Staking.sol:575",
      "Staking.sol:579"
    ],
    "claim": "When an epoch was never initialized, `getEpochPoolSize()` returns the contract's current live balance (`stableCoinBalances` for stables, `balanceOf(address(this))` for non-stables) rather than the pool size that actually existed during the requested epoch.",
    "impact": "Past epoch accounting remains mutable until each missed epoch is explicitly backfilled. Any present-day balance change can rewrite the apparent denominator of older epochs, which can skew reward calculations, make historical accounting non-deterministic, or let an attacker manipulate claims for dormant periods.",
    "paths": [
      "A pool becomes dormant and several epochs are left uninitialized.",
      "Before rewards for one of those past epochs are calculated, an attacker changes the current pool balance via deposit, withdrawal, or direct transfer.",
      "`getEpochPoolSize(token, oldEpoch)` now returns the manipulated current balance instead of the old epoch's real size."
    ]
  },
  {
    "id": "F-010",
    "severity": "Low",
    "confidence": "low",
    "title": "Bootstrap deposits more than one epoch early receive multipliers above 100%",
    "locations": [
      "Staking.sol:90",
      "Staking.sol:92",
      "Staking.sol:140",
      "Staking.sol:166",
      "Staking.sol:585",
      "Staking.sol:590"
    ],
    "claim": "`currentEpochMultiplier()` does not cap the epoch-0 multiplier at `BASE_MULTIPLIER`, so deposits made earlier than one full `epochDuration` before `epoch1Start` receive a multiplier greater than 1e18.",
    "impact": "If the contract is live long enough before `epoch1Start`, bootstrap deposits can overstate epoch-0 effective stake and inflate the copied pool size for the first real epoch. That distorts first-epoch reward accounting and can leave part of the reward budget unallocatable or misallocated.",
    "paths": [
      "The contract accepts deposits more than 28 days before `epoch1Start`.",
      "A user deposits during epoch 0 and gets `currentEpochMultiplier() > BASE_MULTIPLIER`.",
      "The inflated epoch-0 pool size is later propagated when epoch 1 is initialized from epoch 0."
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
