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
    "title": "Reward emissions are not backed by reserved mint capacity",
    "locations": [
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:90",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:115",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:283",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/OnDemandToken.sol:20",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/OnDemandToken.sol:32",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/MintableToken.sol:11",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/MintableToken.sol:46"
    ],
    "claim": "`StakingRewards` only checks its own cumulative `totalRewardsSupply` against `maxAllowedTotalSupply`, but it never accounts for `MintableToken.everMinted` or reserves a dedicated portion of the cap for itself. Because `OnDemandToken` explicitly supports multiple minters, rewards can be scheduled successfully and later become unclaimable when `_getReward()` hits the token's global mint cap.",
    "impact": "If the token owner or another authorized minter mints reward tokens elsewhere, the staking farm becomes insolvent: stakers accrue rewards normally, but `getReward()` and `exit()` eventually revert on mint. This can permanently deny already-promised rewards to every participant.",
    "paths": [
      "Owner enables another minter via `OnDemandToken.setupMinter()` or mints directly as owner.",
      "Rewards distributor calls `notifyRewardAmount()` and users stake normally.",
      "External minting consumes the shared `maxAllowedTotalSupply` budget.",
      "A later `getReward()`/`exit()` call reaches `OnDemandToken.mint()`, which reverts in `MintableToken._assertMaxSupply()`."
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Unvested or canceled emissions still consume the lifetime reward cap",
    "locations": [
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:95",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:115",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:140",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:219"
    ],
    "claim": "`timeData.totalRewardsSupply` increases immediately when `notifyRewardAmount()` is called, but reward tokens are minted only when users later claim. Any rewards that pass while `_totalSupply == 0`, are stranded by `finishFarming()`, or are lost to integer-division truncation are never mintable again, yet they still count against the lifetime cap forever.",
    "impact": "Large parts of the advertised reward budget can be burned without paying anyone. After enough empty or aborted periods, `notifyRewardAmount()` starts reverting even though the corresponding tokens were never minted, permanently disabling future farming campaigns and underpaying stakers.",
    "paths": [
      "`notifyRewardAmount(largeAmount)` while `_totalSupply == 0`; wait until the period has mostly or fully elapsed; the first later stake advances `lastUpdateTime` without assigning the skipped rewards, but `totalRewardsSupply` remains fully consumed.",
      "`notifyRewardAmount(largeAmount)` and then call `finishFarming()` early; the undistributed remainder becomes unreachable forever while still counting toward `maxEverTotalRewards`."
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "Stake accounting becomes insolvent with fee-on-transfer or rebasing staking tokens",
    "locations": [
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:242",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:249",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:262",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:265"
    ],
    "claim": "`_stake()` credits the requested `amount` before verifying how many staking tokens were actually received, and `_withdraw()` always tries to send back the nominal amount. With deflationary, fee-on-transfer, or rebasing staking tokens, internal balances diverge from the contract's real holdings.",
    "impact": "A user can be credited for more stake than the pool actually received, earn rewards on the inflated balance, and later withdraw the full nominal amount. The shortfall is taken from other depositors if enough tokens remain, or honest withdrawals start reverting once the pool becomes insolvent.",
    "paths": [
      "Use a staking token that burns or taxes transfers.",
      "Stake 100 tokens; the contract receives less (for example 90) but records a 100-token position.",
      "Accrue rewards on the inflated 100-token balance, then withdraw 100.",
      "The missing amount is effectively paid by later users or causes pool-wide withdrawal failures."
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "low",
    "title": "96-bit reward accounting can wrap and overbook rewards",
    "locations": [
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:20",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:90",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:115",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/staking/StakingRewards.sol:118",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/MintableToken.sol:11",
      "0xb3fb1d01b07a706736ca175f827e4f56021b85de/contracts/interfaces/MintableToken.sol:46"
    ],
    "claim": "`StakingRewards` stores `totalRewardsSupply` as `uint96`, but compares it against a `uint256 maxEverTotalRewards`. If the reward token's configured cap exceeds `2^96 - 1`, `timeData.totalRewardsSupply = uint96(totalRewardsSupply)` truncates the tracked value and allows later `notifyRewardAmount()` calls to over-schedule rewards.",
    "impact": "The farm can promise more rewards than the token is able to mint. Users then accumulate apparently valid rewards that later revert during payout once `MintableToken.everMinted` reaches the true cap.",
    "paths": [
      "Deploy with `maxAllowedTotalSupply > 2^96 - 1`.",
      "Call `notifyRewardAmount()` with a value that pushes cumulative rewards above the 96-bit range.",
      "Storage truncation wraps `timeData.totalRewardsSupply` to a smaller number.",
      "Subsequent notifications succeed against the wrapped value, but future `getReward()` calls eventually revert in `MintableToken._assertMaxSupply()`."
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
