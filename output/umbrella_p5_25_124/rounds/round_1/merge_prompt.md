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
    "title": "Unchecked subtraction in `withdraw()` lets any caller drain arbitrary staking tokens",
    "locations": [
      "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:201",
      "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:258",
      "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:262",
      "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:263",
      "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:265"
    ],
    "claim": "`withdraw()` forwards user-controlled `amount` into `_withdraw()` without checking `amount <= _balances[user]`, and Solidity 0.7.5 does not automatically check arithmetic. The raw subtractions of `_totalSupply` and `_balances[user]` therefore wrap on underflow, after which the contract still executes a real `stakingToken.transfer(recipient, amount)`.",
    "impact": "Any address, including one with zero stake, can withdraw arbitrary staking tokens from the farm up to the contract's token balance. This drains all deposited principal and corrupts accounting, breaking reward distribution for remaining users.",
    "paths": [
      "Call `withdraw(amount)` from an address with zero or insufficient recorded stake",
      "`_withdraw()` underflows `_totalSupply` and `_balances[msg.sender]`",
      "The farm transfers real staking tokens to the attacker",
      "Repeat until the farm's staking-token balance is exhausted"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Rewards are scheduled against a shared lifetime mint cap, so accrued rewards can become permanently unclaimable",
    "locations": [
      "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:95",
      "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:115",
      "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:283",
      "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/MintableToken.sol:46",
      "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/OnDemandToken.sol:20",
      "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/OnDemandToken.sol:32"
    ],
    "claim": "`notifyRewardAmount()` only checks a farm-local `timeData.totalRewardsSupply + _reward <= maxEverTotalRewards`, but actual mintability is enforced later by `MintableToken.everMinted` inside `OnDemandToken.mint()`. Because the reward token's cap is global and can already be partially consumed before scheduling, or consumed later by the owner/other minters, the farm can promise rewards that are not actually reserved.",
    "impact": "Stakers can accrue rewards that later revert in `getReward()` and `exit()` once the shared mint cap is exhausted. This creates protocol insolvency for rewards, blocks reward claims, and makes the one-shot `exit()` flow unusable for users with pending rewards.",
    "paths": [
      "Some of the reward token's lifetime cap is already used before the farm schedules a campaign, or another authorized minter consumes cap after scheduling",
      "`notifyRewardAmount(_reward)` succeeds because it ignores `everMinted` and shared-cap consumption",
      "Users stake and accrue rewards normally",
      "`getReward()` / `exit()` calls `OnDemandToken.mint()`",
      "`MintableToken._assertMaxSupply()` reverts because the global cap has been exhausted"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "low",
    "title": "Stake accounting trusts the requested amount instead of the tokens actually received",
    "locations": [
      "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:242",
      "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:243",
      "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:249"
    ],
    "claim": "`_stake()` credits `_totalSupply` and `_balances[user]` with the caller-supplied `amount` before verifying how many staking tokens were actually received. If the staking token is fee-on-transfer, rebasing, or otherwise non-standard, internal balances can exceed the farm's real token balance.",
    "impact": "A depositor can become over-credited relative to the assets received by the farm, allowing later withdrawals to extract value from other stakers or causing withdrawals to revert once the contract runs short of staking tokens.",
    "paths": [
      "Use a taxed / deflationary staking token transfer path",
      "Call `stake(amount)` and get credited for the full `amount`",
      "The farm receives fewer than `amount` tokens",
      "Withdraw the inflated recorded balance or leave the pool insolvent for later withdrawers"
    ]
  }
]

```

### Agent: opencode_1
```
I need to audit the smart contracts in the specified directory. Let me first explore the directory structure and read the contract files.
Now let me read the interface files to understand the full picture:
Now I have a clear picture of the vulnerabilities. Let me analyze and compile my findings:

Based on my analysis, I've identified the following security vulnerabilities:

## Critical Finding 1: Integer Underflow in _withdraw()

In `StakingRewards.sol:258-268`, the `_withdraw` function performs subtraction without checking if the amount exceeds the user's balance or total supply. This causes an underflow when the amount is larger than the user's recorded stake, but the token transfer still executes, allowing theft of staking tokens.

## Critical Finding 2: Missing Validation in withdraw()

The `withdraw()` function at line 201-203 does not validate that the caller has sufficient balance before calling `_withdraw()`. Combined with the underflow vulnerability, anyone can drain the staking pool.

## High Finding 3: Shared Mint Cap Insolvency

The staking rewards and the reward token share the same `maxAllowedTotalSupply` (line 90 in StakingRewards.sol). The staking farm uses `totalRewardsSupply` to track scheduled rewards while the token uses `everMinted` to track minted supply. If the token has already been minted to the cap, `notifyRewardAmount()` will fail, causing permanent lockup of staked funds.

## High Finding 4: Insufficient Access Control on withdraw()

The `withdraw()` function allows any caller to withdraw for any user (line 202 uses `msg.sender`), but there's no validation that the caller actually has the tokens to withdraw, leading to the underflow exploit.
Now I'll compile the final JSON array:
[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Integer Underflow in _withdraw() Allows Draining Staking Pool",
    "locations": ["onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:262-263"],
    "claim": "The _withdraw() function subtracts amount from _totalSupply and _balances[user] without validating that amount <= _balances[user], causing an underflow when amount exceeds the user's recorded stake. The staking token transfer executes AFTER the underflow, allowing attackers to drain staking tokens from the pool.",
    "impact": "An attacker can call withdraw() with an amount larger than their recorded balance, triggering underflow on _totalSupply and _balances, but the token transfer still executes. This allows draining all staking tokens from the contract pool.",
    "paths": ["1. Attacker calls withdraw(type(uint256).max) on StakingRewards contract", "2. _withdraw() computes _totalSupply - type(uint256).max causing underflow", "3. _balances[attacker] underflows to a huge number", "4. stakingToken.transfer() executes and sends real tokens to attacker", "5. Attacker repeats to drain entire staking pool"]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "Missing Balance Check in withdraw() Enables Exploit",
    "locations": ["onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:201-203"],
    "claim": "The withdraw() function does not validate that the caller has sufficient balance before calling _withdraw(). Combined with the underflow vulnerability in _withdraw(), this allows any user to drain the staking pool regardless of their actual staked amount.",
    "impact": "Any user can call withdraw() with an arbitrary amount and drain staking tokens from the contract, regardless of their actual staked balance.",
    "paths": ["1. User with 0 staked tokens calls withdraw(1) or withdraw(type(uint256).max)", "2. No balance check is performed before calling _withdraw()", "3. Underflow occurs in _withdraw() and tokens are transferred"]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "Shared Mint Cap Between Staking Rewards and Reward Token Causes Insolvency",
    "locations": ["onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:90", "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:116", "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/MintableToken.sol:46-49"],
    "claim": "The staking rewards contract and the reward token share the same maxAllowedTotalSupply. The staking farm tracks scheduled rewards in totalRewardsSupply while the token tracks minted supply in everMinted. If the reward token has been minted to the cap before notifyRewardAmount() is called, the staking farm cannot schedule new rewards, causing permanent lockup of staker funds.",
    "impact": "If the reward token reaches maxAllowedTotalSupply before staking rewards are scheduled, stakers cannot claim their earned rewards. The farm becomes permanently insolvent - staked funds cannot be recovered and earned rewards cannot be distributed.",
    "paths": ["1. External minter mints reward tokens up to maxAllowedTotalSupply", "2. Staking farm attempts to schedule new rewards via notifyRewardAmount()", "3. require(totalRewardsSupply <= maxEverTotalRewards) fails at line 116", "4. Staking rewards cannot be scheduled - stakers lose all earned rewards", "5. Stakers cannot exit their position"]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "RescueToken Allows Owner to Steal Staking Tokens",
    "locations": ["onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:167-175"],
    "claim": "The rescueToken() function allows the owner to transfer staking tokens out of the contract as long as _totalSupply <= stakingToken.balanceOf(contract) - _amount. The owner can gradually drain staking tokens, eventually leaving stakers unable to withdraw their staked tokens.",
    "impact": "A malicious or compromised owner can drain staking tokens through repeated rescueToken() calls, causing stakers to lose their staked funds when attempting to withdraw.",
    "paths": ["1. Owner calls rescueToken(stakingToken, owner, amount) repeatedly", "2. Each call reduces stakingToken.balanceOf(contract) while _totalSupply remains", "3. When balance becomes insufficient, stakers cannot withdraw their tokens", "4. All staked funds become locked or lost"]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "getReward() Mints Tokens Without Checking Reward Token Supply",
    "locations": ["onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:272-286", "onchain_auto/0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/MintableToken.sol:46-49"],
    "claim": "The _getReward() function calls OnDemandToken.mint() to reward stakers without verifying that the mint would succeed. If the reward token's everMinted + rewardAmount exceeds maxAllowedTotalSupply, the transaction reverts and stakers lose their earned rewards.",
    "impact": "Stakers may lose their earned rewards if the reward token approaches its cap. When getReward() is called and mint would exceed the cap, the transaction reverts and the staker loses their pending rewards permanently.",
    "paths": ["1. Staker earns rewards over time via staking", "2. Other parties consume the mint cap (external mints or notifyRewardAmount)", "3. Staker calls getReward() to claim earned tokens", "4. OnDemandToken.mint() fails due to total supply cap exceeded", "5. Staker loses pending rewards - transaction reverts"]
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
