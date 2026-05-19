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
    "severity": "High",
    "confidence": "high",
    "title": "Zero-amount withdrawals can permanently disable emergency exits for an entire token",
    "locations": [
      "Staking.sol:363",
      "Staking.sol:385",
      "Staking.sol:490"
    ],
    "claim": "The `withdraw` function does not require `amount > 0` and unconditionally sets `lastWithdrawEpochId[tokenAddress] = currentEpoch`. Because `emergencyWithdraw` is gated by `(getCurrentEpoch() - lastWithdrawEpochId[tokenAddress]) >= 10`, any account with even a dust balance can call `withdraw(token, 0)` once per epoch and keep the emergency path disabled for every staker of that token forever.",
    "impact": "A single griefing staker can globally DoS the fallback withdrawal mechanism. If ordinary withdrawals stop working for that token, all affected users can be trapped indefinitely because the 10-epoch timer is continually reset at zero cost.",
    "paths": [
      "Attacker deposits a minimal amount of a non-stable token",
      "Attacker calls `withdraw(token, 0)` once each epoch",
      "Victims calling `emergencyWithdraw(token)` always fail because `lastWithdrawEpochId[token]` never gets 10 epochs old"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "medium",
    "title": "Emergency withdrawals remove principal without clearing staking checkpoints or pool snapshots",
    "locations": [
      "Staking.sol:487",
      "Staking.sol:495",
      "Staking.sol:508",
      "Staking.sol:558"
    ],
    "claim": "`emergencyWithdraw` only zeroes `balances[msg.sender][tokenAddress]` and transfers tokens out. It does not update `balanceCheckpoints` or `poolSize`, even though `getEpochUserBalance` and `getEpochPoolSize` rely on those structures for epoch accounting.",
    "impact": "After taking back all principal, a user can still appear staked in current and future epoch snapshots. Any reward, voting-weight, or accounting logic that trusts these epoch views can overpay exited users and permanently misallocate rewards across the pool.",
    "paths": [
      "User stakes a non-stable token and accrues checkpoints",
      "After the emergency condition is met, user calls `emergencyWithdraw(token)`",
      "Subsequent calls to `getEpochUserBalance(user, token, epoch)` still read the stale checkpoint history instead of zero"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "Historical pool sizes are retroactively mutable for any epoch left uninitialized",
    "locations": [
      "Staking.sol:466",
      "Staking.sol:558",
      "Staking.sol:572",
      "Staking.sol:579"
    ],
    "claim": "`getEpochPoolSize` claims to return the amount locked during a specific epoch, but if that epoch was never initialized it falls back to the contract's current token balance (`stableCoinBalances` or `token.balanceOf(address(this))`). Because epochs are lazily initialized, later deposits and withdrawals can change the reported size of past epochs.",
    "impact": "An attacker can manipulate reward denominators and historical accounting after the fact for skipped epochs. Any settlement code that queries `getEpochPoolSize` lazily can be fed a rewritten past pool size rather than the true balance that existed during that epoch.",
    "paths": [
      "Epoch N passes without any deposit/withdraw, so `poolSize[token][N]` is never initialized",
      "In a later epoch, an attacker changes the contract's current balance for that token",
      "A reward or accounting query for `getEpochPoolSize(token, N)` now returns the manipulated current balance instead of the real epoch-N size"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "Arbitrary-token deposits credit the requested amount instead of the amount actually received",
    "locations": [
      "Staking.sol:113",
      "Staking.sol:129",
      "Staking.sol:136",
      "Staking.sol:153"
    ],
    "claim": "For non-stable tokens, `deposit` accepts any `tokenAddress`, calls `transferFrom`, and then credits `balances[msg.sender][tokenAddress] += amount` and checkpoint data using the caller-supplied `amount`. The code never measures how many tokens were really received, so fee-on-transfer or malicious ERC20s can mint more stake than backing assets.",
    "impact": "Attackers can create undercollateralized positions in a token pool. If honest users later provide liquidity for the same token, the attacker can withdraw more than they actually contributed; if rewards are based on stake snapshots, they can also farm rewards with less or no real capital.",
    "paths": [
      "Attacker deposits a fee-on-transfer or malicious token as a non-stable asset",
      "The token transfers less than `amount` (or otherwise under-delivers), but the contract records the full `amount` as staked",
      "The attacker later withdraws the inflated balance or uses the inflated checkpoints to capture outsized rewards"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "Compound error codes are ignored, allowing silent redemption and mint failures to desynchronize accounting",
    "locations": [
      "Staking.sol:259",
      "Staking.sol:265",
      "Staking.sol:321",
      "Staking.sol:340",
      "Staking.sol:372"
    ],
    "claim": "Compound's `mint`, `redeem`, and `redeemUnderlying` return numeric error codes instead of reverting on failure, but this contract ignores those return values everywhere. Internal balances are updated before proving the Compound action actually succeeded.",
    "impact": "If Compound returns a non-zero error code due to market illiquidity, pause, or another failure, the contract can continue with stale assumptions. That can leave user withdrawals temporarily locked, make pool accounting inconsistent with real holdings, or cause unrelated idle funds to be used as if a redemption succeeded.",
    "paths": [
      "A stablecoin withdrawal calls `_redeemFromCompound(token, amount)` during a period where Compound returns a non-zero error code",
      "The contract has already decreased `balances` and `stableCoinBalances` before checking whether funds were actually redeemed",
      "Subsequent transfers and accounting proceed from an incorrect asset state"
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
