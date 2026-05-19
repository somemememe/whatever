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
    "confidence": "high",
    "title": "Instant withdrawals can burn full shares but return only a fraction of the owed ETH",
    "locations": [
      "contracts/StoneVault.sol:305",
      "contracts/StoneVault.sol:307",
      "contracts/StoneVault.sol:320",
      "contracts/strategies/StrategyController.sol:186",
      "contracts/strategies/StrategyController.sol:191"
    ],
    "claim": "StoneVault burns the caller's STONE before verifying that StrategyController can actually source the requested ETH, while StrategyController.forceWithdraw() pulls funds from each strategy using configured target ratios instead of actual live positions. If positions drift or one strategy is illiquid, the user loses the burned shares and only receives the partial amount returned.",
    "impact": "Users can suffer direct, irreversible loss during instant withdrawals even when the controller still has enough aggregate liquidity across strategies.",
    "paths": [
      "Strategy balances drift away from configured ratios through yield, losses, or partial withdrawals.",
      "A user calls instantWithdraw() with _shares and StoneVault burns the full share amount.",
      "StrategyController._forceWithdraw() asks each strategy for ratio-based amounts instead of its actual available balance.",
      "The controller returns less ETH than the burned shares were worth, and the user has no way to recover the missing value."
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "medium",
    "title": "First depositor can capture any ETH already sitting in the vault before round 1 starts",
    "locations": [
      "contracts/StoneVault.sol:157",
      "contracts/StoneVault.sol:167",
      "contracts/StoneVault.sol:345",
      "contracts/StoneVault.sol:374",
      "contracts/StoneVault.sol:436",
      "contracts/StoneVault.sol:444"
    ],
    "claim": "currentSharePrice() hardcodes 1e18 while latestRoundID == 0, so deposits before the first rollover ignore any ETH already present in AssetsVault or strategies. A late attacker can mint at par against a vault that already contains seeded assets.",
    "impact": "Any pre-seeded ETH, accidental transfers, or preexisting strategy value can be appropriated by the first public depositor once round 1 is created.",
    "paths": [
      "ETH is sent to AssetsVault or an initialized strategy before the first rollToNextRound().",
      "An attacker deposits a minimal amount while latestRoundID is still 0 and receives shares at a fixed 1 ETH/share price.",
      "When rollToNextRound() eventually runs, the previously ignored assets become reflected in share price.",
      "The attacker now owns shares backed by the preexisting assets and can withdraw disproportionate value."
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Remote bridge pause, cap, and price-feed messages always fail because Stone never handles its custom packet types",
    "locations": [
      "contracts/token/Stone.sol:100",
      "contracts/token/Stone.sol:140",
      "contracts/token/Stone.sol:170",
      "@layerzerolabs/solidity-examples/contracts/token/oft/OFTCore.sol:46",
      "@layerzerolabs/solidity-examples/contracts/token/oft/OFTCore.sol:49",
      "@layerzerolabs/solidity-examples/contracts/lzApp/NonblockingLzApp.sol:27",
      "@layerzerolabs/solidity-examples/contracts/lzApp/NonblockingLzApp.sol:33"
    ],
    "claim": "Stone sends PT_FEED, PT_SET_ENABLE, and PT_SET_CAP packets, but it inherits OFTCore._nonblockingLzReceive(), which only accepts PT_SEND and reverts on every other packet type. Those admin messages are therefore stored as failed LayerZero messages instead of being applied on the destination chain.",
    "impact": "Cross-chain emergency controls are nonfunctional: remote bridge instances cannot actually be paused or have their caps updated, leaving intended safety controls unusable during incidents.",
    "paths": [
      "The owner calls setEnableFor() or setCapFor() for another chain, or anyone calls updatePrice().",
      "Stone sends a PT_SET_ENABLE, PT_SET_CAP, or PT_FEED payload over LayerZero.",
      "The destination Stone contract routes the payload into OFTCore._nonblockingLzReceive().",
      "OFTCore rejects the packet as an unknown type, so the remote state is never updated."
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "A withdrawer can receive all ETH stranded in StrategyController even when they only requested a small amount",
    "locations": [
      "contracts/strategies/StrategyController.sol:58",
      "contracts/strategies/StrategyController.sol:61",
      "contracts/strategies/StrategyController.sol:63",
      "contracts/StoneVault.sol:320",
      "contracts/StoneVault.sol:322",
      "contracts/StoneVault.sol:342"
    ],
    "claim": "If StrategyController already holds ETH and its balance is at least the requested withdrawal amount, forceWithdraw() repays the entire controller balance to AssetsVault and reports that full balance as actualAmount instead of capping it at _amount. StoneVault then forwards that windfall to the withdrawing user.",
    "impact": "Any ETH that reaches the controller outside the normal happy path, such as delayed strategy payouts or forced transfers, can be stolen by the next user who triggers a small instant withdrawal.",
    "paths": [
      "ETH accumulates on StrategyController through a delayed strategy return, accidental transfer, or forced send.",
      "Vault idle liquidity is insufficient, so StoneVault calls StrategyController.forceWithdraw() during instantWithdraw().",
      "The requested amount is smaller than or equal to the controller's existing ETH balance.",
      "forceWithdraw() returns the full controller balance, and StoneVault pays that entire amount to the withdrawing user."
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Any post-settlement insolvency makes share-price math underflow and blocks recapitalization flows",
    "locations": [
      "contracts/StoneVault.sol:157",
      "contracts/StoneVault.sol:295",
      "contracts/StoneVault.sol:353",
      "contracts/StoneVault.sol:447",
      "contracts/StoneVault.sol:449"
    ],
    "claim": "currentSharePrice() subtracts withdrawableAmountInPast from total assets without any insolvency handling. If strategy losses reduce total assets below reserved past withdrawals, the subtraction underflows and reverts.",
    "impact": "Once the vault becomes partially insolvent after a round is settled, core flows that depend on currentSharePrice(), including new deposits and future round rolls, can become impossible, preventing recapitalization and worsening the lockup.",
    "paths": [
      "A round is settled and withdrawableAmountInPast is reserved for queued withdrawals.",
      "Before those users finish claiming, strategy assets fall below the reserved liability.",
      "A later deposit(), instantWithdraw(_shares), or rollToNextRound() calls currentSharePrice().",
      "The assets-minus-liabilities calculation underflows and the transaction reverts."
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "medium",
    "title": "rollToNextRound is reentrant through strategy callbacks and updates round accounting only after external calls",
    "locations": [
      "contracts/StoneVault.sol:345",
      "contracts/StoneVault.sol:372",
      "contracts/StoneVault.sol:375",
      "contracts/StoneVault.sol:380",
      "contracts/strategies/StrategyController.sol:149",
      "contracts/strategies/StrategyController.sol:155",
      "contracts/strategies/StrategyController.sol:300"
    ],
    "claim": "StoneVault.rollToNextRound() performs multiple external strategy interactions via StrategyController before it updates latestRoundID, settlementTime, and withdrawal accounting, and it is not protected by nonReentrant. A reentering strategy can invoke rollToNextRound() again against stale state.",
    "impact": "A buggy or malicious strategy can corrupt round sequencing and withdrawal settlement, potentially creating inconsistent prices or locking users into broken accounting.",
    "paths": [
      "rollToNextRound() calls StrategyController.rebaseStrategies().",
      "The controller calls a strategy's deposit(), withdraw(), or clear().",
      "That strategy reenters StoneVault.rollToNextRound() before the outer call updates round state.",
      "Inner and outer calls write round data from different snapshots, leaving inconsistent accounting."
    ]
  },
  {
    "id": "F-007",
    "severity": "Low",
    "confidence": "high",
    "title": "Unvalidated strategy addresses can permanently brick pricing and rebalancing",
    "locations": [
      "contracts/strategies/StrategyController.sol:40",
      "contracts/strategies/StrategyController.sol:48",
      "contracts/strategies/StrategyController.sol:78",
      "contracts/strategies/StrategyController.sol:81",
      "contracts/strategies/StrategyController.sol:199",
      "contracts/strategies/StrategyController.sol:319"
    ],
    "claim": "StrategyController._initStrategies() and addStrategy() accept arbitrary addresses without checking that they are real strategy contracts controlled by this controller. The controller later blindly calls getAllValue(), getInvestedValue(), withdraw(), and clear() on those addresses throughout pricing, rebalancing, and recovery paths.",
    "impact": "A single bad strategy address can make rollToNextRound(), currentSharePrice(), and even destroyStrategy() revert, creating a protocol-wide DoS that is difficult to recover from.",
    "paths": [
      "An incorrect strategy address is supplied at deployment or later added through addStrategy().",
      "The controller attempts to query or rebalance that address during pricing or rollover.",
      "The external call reverts or returns malformed data.",
      "Core vault flows fail and the bad strategy can be impossible to cleanly remove."
    ]
  }
]

```

### Agent: opencode_1
```
Let me read the main custom contracts to identify security vulnerabilities:
Now let me also look at some of the LayerZero contracts for potential cross-chain vulnerabilities:
Based on my thorough analysis of all the contracts, I've identified several security vulnerabilities. Let me generate the JSON findings:

```json
[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Share Price Calculation Error Causes User Fund Loss in instantWithdraw",
    "locations": [
      "contracts/StoneVault.sol:289-330"
    ],
    "claim": "The instantWithdraw function calculates share price incorrectly - it uses the MINIMUM of preview price and current price (lines 296-302), while deposits use the MAXIMUM (lines 162-164). This asymmetry means users withdrawing via shares receive less ETH than they should.",
    "impact": "Users performing instant withdrawals lose significant value. Since deposits use max share price and withdrawals use min share price, users get unfair treatment. An attacker can deposit during high price and withdraw during low price, extracting value from the protocol.",
    "paths": [
      "User calls instantWithdraw with _shares parameter during a period where currentSharePrice > latestSharePrice",
      "User receives fewer ETH than they should based on current valuation"
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "Fee Not Applied to Share-Based Withdrawals",
    "locations": [
      "contracts/StoneVault.sol:289-342"
    ],
    "claim": "The withdraw fee (withdrawFeeRate) is only applied when _amount != 0 (lines 335-341), but when withdrawing via _shares parameter, no fee is charged. This allows users to bypass withdrawal fees by using the share-based withdrawal path.",
    "impact": "Users can bypass the withdrawal fee mechanism by always using share-based instantWithdraw. This leads to loss of expected fee revenue for the protocol.",
    "paths": [
      "User calls instantWithdraw with _shares != 0 and _amount == 0",
      "No withdrawal fee is deducted from the withdrawn amount"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "Lack of Slippage Protection in Rebalancing",
    "locations": [
      "contracts/strategies/StrategyController.sol:141-157"
    ],
    "claim": "The _rebase function processes strategy deposits and withdrawals sequentially without any slippage protection. When moving funds between strategies, if price impacts occur during the first iterations, subsequent allocations will be affected by worse rates.",
    "impact": "During rebalancing, later strategies may receive worse execution prices due to changes in liquidity after earlier transactions. This can cause value leakage from the protocol.",
    "paths": [
      "Owner or automation triggers rollToNextRound",
      "StrategyController iterates through strategies sequentially executing deposits/withdrawals",
      "Market impact on early strategies affects execution for later ones"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "Unlimited Owner Control Over Token Transfers",
    "locations": [
      "contracts/token/Stone.sol:119-151"
    ],
    "claim": "The setEnableFor function allows the owner to completely disable all sendFrom functionality by setting enable=false. Once disabled, no user can transfer tokens, effectively freezing all funds in the contract.",
    "impact": "Owner can permanently lock user funds by setting enable=false. This is a centralization risk where users have no recourse if the owner acts maliciously or becomes compromised.",
    "paths": [
      "Owner calls setEnableFor with _flag=false for the local chain",
      "All users lose ability to transfer their STONE tokens"
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "Unverified Strategy Address Can Be Added",
    "locations": [
      "contracts/strategies/StrategyController.sol:78-82"
    ],
    "claim": "The addStrategy function only checks that the strategy doesn't already exist in the EnumerableSet, but does not verify the strategy is a valid contract or that it has the expected interface. A malicious address could be added.",
    "impact": "Attacker could add a malicious contract that pretends to be a strategy. While there is a controller check in _setStrategies, the addStrategy lacks this verification.",
    "paths": [
      "Attacker who gains proposal access calls addStrategy with malicious address",
      "Malicious strategy could steal funds or return incorrect values"
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "high",
    "title": "Single-Point Proposal Role Modification",
    "locations": [
      "contracts/StoneVault.sol:426-428"
    ],
    "claim": "The updateProposal function allows the current proposal to transfer the proposal role to any address without any timelock or confirmation. There is no delay or multi-step process.",
    "impact": "If the proposal address is compromised or becomes malicious, it can immediately transfer control to another address, draining funds or changing protocol parameters without users' knowledge.",
    "paths": [
      "Compromised proposal calls updateProposal with attacker-controlled address",
      "Attacker gains proposal privileges immediately"
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "high",
    "title": "Migration Without User Consent",
    "locations": [
      "contracts/StoneVault.sol:430-434"
    ],
    "claim": "The migrateVault function can change the vault address in Minter, AssetsVault, and StrategyController without any user notification or opt-out mechanism. Users' funds are moved to a new vault address controlled by the proposal.",
    "impact": "Proposal can migrate all user funds to a new vault address. Users have no way to exit or recover their funds if the new vault is malicious or defective.",
    "paths": [
      "Proposal calls migrateVault with new vault address",
      "All user deposits and pending withdrawals are redirected to new vault"
    ]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Potential Division by Zero in VaultMath",
    "locations": [
      "contracts/libraries/VaultMath.sol:11"
    ],
    "claim": "The assetToShares function only checks _assetPerShare > 1, but does not handle the case when totalSupply is zero in share calculations. If totalStone == 0, share calculations could produce unexpected results.",
    "impact": "In edge cases where total supply is 0 or very small, share calculations could be manipulated or fail.",
    "paths": [
      "First depositor interacts with fresh vault",
      "Share calculations depend on precision that may cause edge cases"
    ]
  },
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "low",
    "title": "Daily Quota Can Be Fully Consumed by Single User",
    "locations": [
      "contracts/token/Stone.sol:70-73"
    ],
    "claim": "The daily quota (cap) can be exhausted by a single user in one transaction. While the check exists to limit total daily cross-chain transfers, a whale can consume the entire quota in one transaction, preventing others from using cross-chain features.",
    "impact": "Legitimate users may be unable to send cross-chain transfers if a whale consumes the daily quota. This creates griefing possibility.",
    "paths": [
      "User with large holdings calls sendFrom with amount = cap - quota[day]",
      "Other users unable to send cross-chain transfers for remainder of day"
    ]
  },
  {
    "id": "F-010",
    "severity": "Low",
    "confidence": "medium",
    "title": "Unchecked Return Value in Strategy Withdrawal",
    "locations": [
      "contracts/strategies/Strategy.sol:35-37"
    ],
    "claim": "The withdraw and instantWithdraw functions in Strategy contract have empty implementations that return 0 as actualAmount. Concrete strategy implementations may not properly return actual withdrawn amounts, leading to accounting errors.",
    "impact": "If a strategy implementation fails to properly track or return actual withdrawn amounts, the vault's accounting will be incorrect, potentially leading to incorrect share price calculations.",
    "paths": [
      "Strategy implementation fails to return accurate withdrawal amounts",
      "Vault calculations use incorrect values, causing share price manipulation"
    ]
  },
  {
    "id": "F-011",
    "severity": "Low",
    "confidence": "high",
    "title": "AssetsVault Can Be Reinitialized",
    "locations": [
      "contracts/AssetsVault.sol:35-37"
    ],
    "claim": "The setNewVault function allows changing the stoneVault address without any validation that the old address was deprecated or that the new address is valid. The AssetsVault can have its permissions redirected.",
    "impact": "If the vault address is changed to an attacker-controlled contract, all assets could be stolen. However, this requires compromising the proposal or vault.",
    "paths": [
      "Proposal or compromised vault calls migrateVault",
      "AssetsVault's stoneVault reference gets updated to new address"
    ]
  },
  {
    "id": "F-012",
    "severity": "Informational",
    "confidence": "high",
    "title": "No Access Control on Stone Contract Initialization",
    "locations": [
      "contracts/token/Stone.sol:31-38"
    ],
    "claim": "The Stone contract constructor sets minter and cap without additional safeguards. The cap can be set to zero, effectively disabling cross-chain transfers from the start.",
    "impact": "If cap is set to 0 during deployment, cross-chain functionality is permanently disabled. While not a vulnerability, this could be unintentional.",
    "paths": [
      "Deployer initializes Stone with cap=0",
      "All cross-chain sendFrom calls will revert due to Exceed cap check"
    ]
  }
]
```

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
