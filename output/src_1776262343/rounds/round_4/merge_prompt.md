Below are findings from 2 agents auditing the same codebase,
plus accumulated findings from previous rounds. You can inspect the source code when needed.

You are the merge and review layer for a audit.

Your task is to read all findings from this round, merge them into the 
summary of distinct issues, compare that round summary against accumulated findings,
and keep new or materially improved findings in the updated list. 
And you are encouraged to find more findings based on these findings and source code.

Use only Solidity source files under the target directory as audit evidence.
Do not inspect or rely on README files, docs, audit reports, discord exports, scripts, broadcasts, or other files outside the target directory.

Downgrade severity or confidence when the issue depends on unusual configuration or weak assumptions. 
Be skeptical of documented behavior and pure owner-only configuration issues, but keep defensible findings when they create realistic protocol-level harm such as fund loss, theft, insolvency, permanent lockup, economic manipulation, or permissionless denial of service.
Review the merged findings before finalizing them, and remove only findings that are clearly non-reportable in a audit's main results.

## Accumulated Findings
[
  {
    "id": "F-001",
    "severity": "High",
    "confidence": "high",
    "title": "Dinero withdrawal finalization condition is inverted",
    "locations": [
      "withdraws/Dinero.sol:55",
      "withdraws/Dinero.sol:71",
      "withdraws/Dinero.sol:87"
    ],
    "claim": "`DineroWithdrawRequestManager.canFinalizeWithdrawRequest` returns `PirexETH.outstandingRedemptions() > totalAssets`, but finalization readiness should require sufficient assets for redemptions. The comparison is inverted.",
    "impact": "Dinero withdraw requests can remain unfinalizable even when they should be redeemable, leaving funds stuck in pending-withdraw state.",
    "paths": [
      "User initiates a Dinero withdrawal request",
      "Referenced batches become dissolved/slashed and assets are available",
      "Outstanding redemptions are less than or equal to request assets",
      "Readiness check still returns false due to inverted comparison, blocking finalize/redeem"
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "medium",
    "title": "Morpho market oracle uses account-agnostic vault price and can misprice pending-withdraw collateral",
    "locations": [
      "routers/MorphoLendingRouter.sol:64",
      "AbstractYieldStrategy.sol:118",
      "AbstractYieldStrategy.sol:123",
      "staking/AbstractStakingStrategy.sol:50",
      "single-sided-lp/AbstractSingleSidedLP.sol:300"
    ],
    "claim": "Morpho markets are configured with `oracle: vault`, so Morpho-side checks depend on the vault oracle path. Borrower-specific pending-withdraw valuation adjustments rely on borrower context (`price(address)` / `t_CurrentAccount`) and may be skipped in account-agnostic oracle reads.",
    "impact": "Collateral can be overvalued for borrowers with pending withdraws, enabling excess borrowing and delayed liquidation, increasing bad-debt risk.",
    "paths": [
      "Borrower enters pending-withdraw state where account-specific valuation should apply",
      "Morpho operations rely on market oracle configured as the vault",
      "Oracle read path is account-agnostic and may not apply borrower-specific pending-withdraw haircut",
      "Borrow/solvency checks can overestimate collateral value"
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "high",
    "title": "LP zero-balance legs create missing withdraw requests that break pending valuation and finalization",
    "locations": [
      "single-sided-lp/AbstractSingleSidedLP.sol:332",
      "single-sided-lp/AbstractSingleSidedLP.sol:363",
      "single-sided-lp/AbstractSingleSidedLP.sol:370",
      "single-sided-lp/AbstractSingleSidedLP.sol:392"
    ],
    "claim": "LP withdraw initiation skips legs with `exitBalances[i] == 0`, creating no request for those legs. Later logic assumes every leg has a request: valuation path requires `hasRequest`, and finalization computes `yieldTokensBurned = w.yieldTokenAmount * sharesToRedeem / w.sharesAmount` even when `w.sharesAmount == 0` for skipped legs.",
    "impact": "Pending-withdraw positions can become unpriceable and matured requests can revert during redemption, disrupting solvency checks and potentially locking exits.",
    "paths": [
      "A proportional LP exit returns zero amount for at least one pool token leg",
      "initiateWithdraw skips request creation for that leg",
      "Account remains pending due to other legs",
      "Valuation reverts on `require(hasRequest)` or finalization reverts on division by zero"
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "Reward debt is advanced even when reward transfer fails",
    "locations": [
      "rewards/AbstractRewardManager.sol:231",
      "rewards/AbstractRewardManager.sol:232",
      "rewards/AbstractRewardManager.sol:242",
      "rewards/AbstractRewardManager.sol:250"
    ],
    "claim": "`_claimRewardToken` updates account `rewardDebt` before attempting transfer, then swallows transfer failures and emits a zero-transfer event. Failed transfers do not preserve claimable rewards.",
    "impact": "Users can permanently lose accrued rewards when transfer fails (blacklist, paused/broken token, non-standard behavior) because accounting is not rolled back.",
    "paths": [
      "User claims rewards",
      "Contract computes `rewardToClaim` and updates `rewardDebt`",
      "Reward token transfer fails or returns false",
      "Function emits zero transfer but keeps updated debt, burning claim"
    ],
    "round": 1,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-005",
    "severity": "Low",
    "confidence": "medium",
    "title": "Zero-yield-token withdraw requests can trigger division-by-zero on finalization accounting",
    "locations": [
      "AbstractYieldStrategy.sol:302",
      "withdraws/AbstractWithdrawRequestManager.sol:111",
      "withdraws/AbstractWithdrawRequestManager.sol:114",
      "withdraws/AbstractWithdrawRequestManager.sol:240",
      "withdraws/AbstractWithdrawRequestManager.sol:326"
    ],
    "claim": "Withdraw initiation does not enforce `yieldTokenAmount > 0`. For dust shares, `convertSharesToYieldToken` can round to zero, creating requests with nonzero shares but `totalYieldTokenAmount == 0`; finalized accounting later divides by `s.totalYieldTokenAmount`.",
    "impact": "Dust positions can be pushed into withdraw-request states that fail to finalize/redeem cleanly.",
    "paths": [
      "Account with very small shares initiates withdraw",
      "`convertSharesToYieldToken` rounds down to zero",
      "Request is recorded with `yieldTokenAmount == 0` and tokenized total set to zero",
      "Finalized pro-rata calculation divides by zero and reverts"
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "high",
    "title": "Ethena zero-duration cooldown mode strands redeemed USDe in cloned holder",
    "locations": [
      "withdraws/Ethena.sol:18",
      "withdraws/Ethena.sol:20",
      "withdraws/Ethena.sol:39",
      "withdraws/Ethena.sol:47"
    ],
    "claim": "If `sUSDe.cooldownDuration() == 0`, `_startCooldown` redeems immediately into the holder. During finalization, `_finalizeCooldown` computes `balanceAfter - balanceBefore` after funds are already present, so `tokensClaimed` becomes zero and redeemed USDe is not forwarded to the vault.",
    "impact": "Withdrawals can finalize with zero payout while user funds remain trapped in per-request holder clones until admin rescue.",
    "paths": [
      "Ethena cooldown duration is set to zero",
      "Withdraw initiation redeems sUSDe directly into the cloned holder",
      "Finalization computes delta balance after funds already arrived",
      "`tokensClaimed` is zero and user receives nothing"
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-008",
    "severity": "Low",
    "confidence": "medium",
    "title": "Dinero withdrawals never request validator exits",
    "locations": [
      "withdraws/Dinero.sol:29",
      "withdraws/Dinero.sol:30"
    ],
    "claim": "Dinero withdrawal initiation hardcodes `shouldTriggerValidatorExit = false` in `PirexETH.initiateRedemption`, so this flow never requests validator exits even when exits are needed to satisfy redemptions.",
    "impact": "Requests can remain pending much longer and may be effectively stuck until external actors trigger exits or provide liquidity.",
    "paths": [
      "User initiates Dinero withdraw during low available redemption liquidity",
      "Manager initiates redemption with `shouldTriggerValidatorExit = false`",
      "No validator exit is requested by this flow",
      "Finalization depends on external actors and can remain unavailable"
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-009",
    "severity": "Low",
    "confidence": "high",
    "title": "Dinero request-id nonce overflows after 65,535 withdrawals and halts new requests",
    "locations": [
      "withdraws/Dinero.sol:10",
      "withdraws/Dinero.sol:32"
    ],
    "claim": "Dinero uses a `uint16` `s_batchNonce` for request-id uniqueness. Under Solidity 0.8 checked arithmetic, `++s_batchNonce` reverts after `type(uint16).max`.",
    "impact": "A finite number of withdrawals can exhaust nonce space and permanently DoS new Dinero withdraw requests unless code is upgraded.",
    "paths": [
      "Repeated withdraw initiations increment `s_batchNonce`",
      "Nonce reaches 65,535",
      "Next `++s_batchNonce` overflows and reverts",
      "All subsequent Dinero withdraw initiations fail"
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-010",
    "severity": "Low",
    "confidence": "medium",
    "title": "Router transfer authorization is not bound to the intended source account",
    "locations": [
      "AbstractYieldStrategy.sol:219",
      "AbstractYieldStrategy.sol:333"
    ],
    "claim": "`allowTransfer` authorizes only destination and amount in transient storage, but `_update` does not verify `from`. While the transient authorization is live, any transfer to the authorized `to` for up to the authorized amount is accepted, regardless of sender address.",
    "impact": "The invariant that native balances cannot be transferred can be bypassed in router-mediated transfer windows, enabling misdirected share movement from unintended holders if a spender already has allowance.",
    "paths": [
      "Router calls `allowTransfer(receiver, amount, currentAccount)`",
      "Authorized spender/market executes transfer path to `receiver` with `from` not equal to intended account",
      "Vault accepts transfer because `_update` checks only `to` and `amount`",
      "Unintended holder shares can be moved"
    ],
    "round": 3,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-011",
    "severity": "Low",
    "confidence": "high",
    "title": "Any whitelisted lending router can delete another router's live position record",
    "locations": [
      "proxy/AddressRegistry.sol:144"
    ],
    "claim": "`clearPosition` only checks that caller is a whitelisted lending router, then unconditionally deletes `accountPositions[account][vault]`. It does not require caller to match the router recorded in that position.",
    "impact": "A buggy or compromised whitelisted router can erase another router's position record, breaking position ownership invariants, blocking normal exit checks on the legitimate router, and enabling conflicting re-entry records.",
    "paths": [
      "Router A opens position for account/vault",
      "Router B (also whitelisted) calls `clearPosition(account, vault)`",
      "Registry entry is deleted despite Router A being owner",
      "Router A `exitPosition` fails `_checkExit` and account can create inconsistent new router state"
    ],
    "round": 3,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-012",
    "severity": "Low",
    "confidence": "low",
    "title": "Sequencer outage protection is skipped on legacy oracle accessors",
    "locations": [
      "oracles/AbstractCustomOracle.sol:51",
      "oracles/AbstractCustomOracle.sol:62",
      "oracles/AbstractCustomOracle.sol:66",
      "oracles/AbstractCustomOracle.sol:70"
    ],
    "claim": "Sequencer/grace-period checks are enforced only in `latestRoundData()`. Legacy Chainlink-style getters (`latestAnswer`, `latestTimestamp`, `latestRound`) return `_calculateBaseToQuote()` directly without `_checkSequencer()`.",
    "impact": "Consumers using legacy accessor methods can read prices during sequencer downtime/grace periods, bypassing intended outage safety checks.",
    "paths": [
      "Sequencer is down or in grace period",
      "Consumer calls `latestAnswer()`/`latestTimestamp()`/`latestRound()` instead of `latestRoundData()`",
      "Oracle returns values without sequencer safety gate"
    ],
    "round": 3,
    "source_agents": [
      "codex_1"
    ]
  }
]

## This Round's Agent Outputs
### Agent: codex_1
```
[
  {
    "id": "F-001",
    "severity": "Medium",
    "confidence": "high",
    "title": "Anyone can prematurely finalize GenericERC4626 withdrawals and freeze away later vault yield",
    "locations": [
      "withdraws/AbstractWithdrawRequestManager.sol:149",
      "withdraws/GenericERC4626.sol:32",
      "withdraws/GenericERC4626.sol:42"
    ],
    "claim": "`finalizeRequestManual` is permissionless, and `GenericERC4626WithdrawRequestManager` treats every request as immediately finalizable and redeems ERC4626 shares at finalization time. A third party can therefore force a pending withdraw to be converted from appreciating ERC4626 shares into idle underlying assets before the owner chooses to redeem.",
    "impact": "After the forced manual finalization, the requester no longer earns the ERC4626 share-price appreciation they should have received by waiting. This enables permissionless griefing that strips post-request yield from ERC4626-backed withdrawals and can underpay users by the foregone appreciation.",
    "paths": [
      "A user initiates a withdraw through a strategy that uses `GenericERC4626WithdrawRequestManager`.",
      "Before the user redeems, any third party calls `finalizeRequestManual(vault, user)`.",
      "The manager immediately calls `IERC4626(YIELD_TOKEN).redeem(...)` and marks the tokenized request finalized.",
      "When the user later redeems, they receive the fixed underlying amount from the earlier redemption instead of the higher amount that the ERC4626 shares would have been worth later."
    ]
  },
  {
    "id": "F-002",
    "severity": "Low",
    "confidence": "high",
    "title": "Partial redemption of finalized withdraw requests strands rounding dust permanently",
    "locations": [
      "withdraws/AbstractWithdrawRequestManager.sol:123",
      "withdraws/AbstractWithdrawRequestManager.sol:135",
      "withdraws/AbstractWithdrawRequestManager.sol:223",
      "withdraws/AbstractWithdrawRequestManager.sol:240"
    ],
    "claim": "When a request has finalized, payout attribution is rounded down proportionally in `_finalizeWithdraw`, and `finalizeAndRedeemWithdrawRequest` rounds down again on partial burns. The contract never tracks or redistributes the residual remainder, so splitting a finalized request across multiple partial redemptions can leave part of `totalWithdraw` unclaimable.",
    "impact": "Users and liquidators can be underpaid by cumulative rounding loss, while the leftover withdraw tokens remain trapped in the manager forever. The loss is small per request but can accumulate over time across tokenized or partially redeemed withdrawals.",
    "paths": [
      "A withdraw request finalizes with `totalWithdraw` not cleanly divisible by `totalYieldTokenAmount`.",
      "The request is redeemed in multiple partial burns or across tokenized holders.",
      "Each redemption floors its pro-rata amount.",
      "The sum of all payouts ends up below `totalWithdraw`, leaving dust stranded in the manager."
    ]
  },
  {
    "id": "F-003",
    "severity": "Low",
    "confidence": "low",
    "title": "Executed proxy upgrades appear replayable without re-arming the 7-day timelock",
    "locations": [
      "proxy/TimelockUpgradeableProxy.sol:40",
      "proxy/TimelockUpgradeableProxy.sol:54",
      "proxy/TimelockUpgradeableProxy.sol:58"
    ],
    "claim": "The proxy never clears `newImplementation` or `upgradeValidAt` after `executeUpgrade`. If `ERC1967Utils.upgradeToAndCall` accepts a call where the implementation is already current, the upgrade admin can reuse the same matured upgrade slot to invoke additional upgrade calldata immediately, without a fresh `initiateUpgrade` delay.",
    "impact": "The intended 7-day governance delay can collapse into a one-time wait, after which privileged reinitializer-style calls against the same implementation may be executed on demand. That weakens the proxy's stated timelock protection for post-upgrade actions.",
    "paths": [
      "The upgrade admin calls `initiateUpgrade(X)` and waits 7 days.",
      "The admin executes `executeUpgrade(data1)` successfully.",
      "Because the pending upgrade fields remain populated, the admin calls `executeUpgrade(data2)` again against the same `newImplementation` without a new delay.",
      "If same-implementation `upgradeToAndCall` is accepted, the second privileged delegatecall executes immediately."
    ]
  }
]

```

### Agent: opencode_1
```
Now, I've conducted a thorough analysis of the contracts, identifying several security vulnerabilities, some of which were already known from the previous round. Based on my detailed code review, I found two new potential issues not previously reported in the known findings list:

1.  **F-013**: A potential division by zero issue in the withdraw flow within `AbstractWithdrawRequestManager` and related staking strategies.
2.  **F-014**: Potential griefing attack in the reward claim process via array manipulation in `AbstractRewardManager`.

I've decided to prioritize the most critical and clearly reproducible issues and am returning a concise JSON array of my findings. I have thoroughly reviewed the codebase and can confirm that the existing findings (F-001 through F-012) cover the major risks. Based on my deep review of the codebase, I will now return the JSON array with my findings.
```json
[
  {
    "id": "F-013",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Division by zero in pending withdraw request valuation",
    "locations": [
      "AbstractWithdrawRequestManager.sol:339"
    ],
    "claim": "When calculating the value of a pending withdraw request, the formula divides by `w.sharesAmount`. If an account has a pending request but zero vault shares (e.g., after full liquidation), this causes a division by zero revert.",
    "impact": "Accounts with pending withdraw requests that have been fully liquidated cannot have their position valued, potentially blocking health factor checks or causing revert in liquidation paths.",
    "paths": [
      "Account enters position → initiates withdraw request → gets fully liquidated → health factor check or liquidation triggers convertToAssets → division by zero"
    ]
  },
  {
    "id": "F-014",
    "severity": "Low",
    "confidence": "low",
    "title": "Tokenize allows transfer to account with different pending request without validation",
    "locations": [
      "AbstractWithdrawRequestManager.sol:176-178"
    ],
    "claim": "The `tokenizeWithdrawRequest` function allows tokenizing a withdraw request to an account that already has a DIFFERENT pending withdraw request (`toWithdraw.requestId != 0 && toWithdraw.requestId != requestId`). The code merges the requests by adding yield token amounts, but the shares amounts are handled inconsistently.",
    "impact": "Potential loss of accounting precision when merging withdraw requests from different vaults. The yield token amounts are summed but shares are added separately, creating a confusing state that could lead to incorrect finalization calculations.",
    "paths": [
      "Account A has pending request for vault X → liquidator calls tokenizeWithdrawRequest to transfer to account B who already has pending request for vault Y → requests get merged incorrectly"
    ]
  },
  {
    "id": "F-015",
    "severity": "Medium",
    "confidence": "medium",
    "title": "LP vault finalize redeem does not verify withdraw request exists before finalizing",
    "locations": [
      "AbstractSingleSidedLP.sol:389-396"
    ],
    "claim": "In the LP vault's `finalizeAndRedeemWithdrawRequest`, there is no explicit check that the account actually has a pending withdraw request before calling `manager.finalizeAndRedeemWithdrawRequest`. If the account does not have a request, the call will revert with unclear error.",
    "impact": "If an LP vault position is exited when there is no pending withdraw request (e.g., a regular exit), the call will revert. While this is mostly a UX issue, it could cause griefing if someone manipulates the state.",
    "paths": [
      "User calls exitPosition on LP vault with shares but no pending withdraw request → revert"
    ]
  },
  {
    "id": "F-016",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Pendle instant redemption PT swap lacks slippage protection on first leg",
    "locations": [
      "PendlePT.sol:86"
    ],
    "claim": "When executing instant redemption on Pendle PT vaults, the first leg of the swap (swapping asset to PT via `PendlePTLib.swapExactTokenForPt`) does not use any slippage parameter from the redeem params. The `minPurchaseAmount` is only checked on the second leg (PT to asset).",
    "impact": "If the Pendle market experiences high slippage or manipulation on the PT purchase leg, users could receive significantly fewer PT tokens than expected, with only the second leg having slippage protection.",
    "paths": [
      "User calls redeemNative on Pendle PT vault → first leg (asset to PT) executes without slippage check → receives less PT → second leg may still succeed but with overall loss"
    ]
  },
  {
    "id": "F-017",
    "severity": "Low",
    "confidence": "medium",
    "title": "LP oracle division by zero when pool has zero total supply",
    "locations": [
      "AbstractLPOracle.sol:85"
    ],
    "claim": "The LP oracle calculates token claims using `balances[i] * POOL_PRECISION / totalSupply`. If the LP pool has zero total supply (e.g., freshly initialized or fully drained), this causes division by zero.",
    "impact": "Oracle price query will revert, potentially blocking any operations that depend on the vault price including entering positions, health factor checks, or liquidations.",
    "paths": [
      "LP pool is drained to zero total supply → any price query on the vault reverts with division by zero"
    ]
  },
  {
    "id": "F-018",
    "severity": "Low",
    "confidence": "low",
    "title": "Reward claim may use stale vault reward state if no vault-level claim occurs",
    "locations": [
      "AbstractRewardManager.sol:148-160"
    ],
    "claim": "In `updateAccountRewards`, the code claims vault rewards if `sharesInEscrow` is true and `accountSharesAfter > 0`, but in other paths it relies on the previous claim timestamp. If no vault-level claim has happened for a while, the accumulated rewards per share may be stale.",
    "impact": "Users claiming rewards may receive less than they are entitled to if the vault rewards haven't been claimed recently. The `claimRewardTokens` function exists but may not be called frequently enough.",
    "paths": [
      "Vault sits idle for extended period → user claims rewards via lending router → receives rewards based on stale accumulator"
    ]
  },
  {
    "id": "F-019",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Morpho liquidation callback does not verify returned shares match requested",
    "locations": [
      "MorphoLendingRouter.sol:252-254"
    ],
    "claim": "In the `_liquidate` function, the returned `sharesToLiquidator` from `MORPHO.liquidate()` is used directly without verifying it matches the requested `sharesToLiquidate`. If Morpho returns fewer shares than requested (e.g., due to insufficient collateral), the liquidator may receive less than expected.",
    "impact": "Liquidators may receive fewer shares than they attempted to liquidate, potentially not covering the debt fully. The health factor may remain positive after liquidation when it should be fully liquidated.",
    "paths": [
      "Liquidator calls liquidate with sharesToLiquidate=100 → Morpho returns sharesToLiquidator=50 due to insufficient collateral → liquidator receives 50 shares but debt may not be fully repaid"
    ]
  },
  {
    "id": "F-020",
    "severity": "Low",
    "confidence": "medium",
    "title": "Reward debt calculation does not handle extreme reward per share values",
    "locations": [
      "AbstractRewardManager.sol:231-234"
    ],
    "claim": "The reward debt calculation uses `(accountSharesAfter * rewardsPerVaultShare) / DEFAULT_PRECISION`. If `rewardsPerVaultShare` is extremely large (possible with high reward emissions and low supply), this could overflow or truncate significantly.",
    "impact": "Users with very small share amounts may receive zero rewards due to rounding, or in extreme cases the calculation could overflow, causing the transaction to revert.",
    "paths": [
      "Vault has very low supply but very high reward emissions → user with small shares claims rewards → receives 0 due to precision loss"
    ]
  },
  {
    "id": "F-021",
    "severity": "Low",
    "confidence": "low",
    "title": "Exit position allows zero shares to be redeemed without validation",
    "locations": [
      "AbstractLendingRouter.sol:113"
    ],
    "claim": "The `exitPosition` function accepts `sharesToRedeem` as a parameter but does not validate that it's greater than zero before proceeding to `_redeemShares`. The burn function does check for zero, but the check happens deeper in the call stack.",
    "impact": "Minor gas waste when users call exitPosition with zero shares. The transaction will proceed through multiple internal calls before reverting at `_burnShares`.",
    "paths": [
      "User calls exitPosition with sharesToRedeem=0 → multiple internal calls → revert at burnShares"
    ]
  }
]
```

```


## Excluded From Direct Audit Scope
Do not keep findings whose reportable root cause exists solely in files matching:
- `interfaces/** `

Those files may still be read as context for in-scope implementation code.


## Output
Return the COMPLETE updated findings list as a JSON array.

Each element must have:
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

Output ONLY valid JSON. No markdown. No prose.
