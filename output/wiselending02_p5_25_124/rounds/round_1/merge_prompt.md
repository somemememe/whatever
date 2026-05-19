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
    "title": "depositExactAmountETHMint skips pool synchronization and mints WETH shares at stale prices",
    "locations": [
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:383",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:364"
    ],
    "claim": "`depositExactAmountETHMint()` calls `_depositExactAmountETH()` directly without the `syncPool(WETH_ADDRESS)` modifier used by the normal ETH deposit path, so it skips `_preparePool`, interest accrual, share-price snapshotting, and the post-action share-price invariant. When WETH interest/yield has accrued since the last sync, an attacker can mint shares against the stale `pseudoTotalPool` and capture value that should belong to existing lenders.",
    "impact": "The WETH pool can be diluted whenever it is out of date. Attackers can repeatedly mint underpriced shares and later redeem them after a sync, stealing accrued interest/yield from existing WETH depositors and potentially bypassing deposit-cap checks that rely on up-to-date pool totals.",
    "paths": [
      "Let WETH interest/yield accrue without syncing the pool.",
      "Call `depositExactAmountETHMint()` instead of `depositExactAmountETH()`.",
      "Receive shares computed from stale WETH pool totals.",
      "After any later sync, withdraw the over-minted shares for more WETH than was fairly deposited."
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Inbound ERC20 accounting trusts `_amount` instead of actual tokens received",
    "locations": [
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:142",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:432",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:510",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:578",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1277",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1318",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:566",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:589"
    ],
    "claim": "Deposits, solely-deposits, repayments, and liquidations all update pool and position accounting using the user-supplied `_amount` before or without verifying the actual post-transfer balance delta. For fee-on-transfer, deflationary, rebasing-on-transfer, or otherwise non-plain ERC20s, the protocol credits more collateral or debt repayment than it actually receives.",
    "impact": "If such a token is listed, attackers can over-credit collateral and over-borrow against it, or repay/liquidate debt with fewer tokens than the protocol assumes. That creates direct lender losses, undercollateralized positions, and insolvency in the affected pools.",
    "paths": [
      "Use a fee-on-transfer collateral token with `depositExactAmount()` or `solelyDeposit()`; the protocol credits full `_amount` even though fewer tokens arrive.",
      "Borrow other assets against the inflated collateral balance.",
      "Use a fee-on-transfer debt token with `paybackExactAmount()` or `paybackExactShares()`; debt is reduced by the nominal amount while the pool receives less.",
      "Use such a token as `_paybackToken` in liquidation; `_coreLiquidation()` reduces victim debt and transfers seized collateral based on `_paybackAmount` before validating how many tokens were actually collected."
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "ERC20 helpers treat `false` return values as success",
    "locations": [
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/TransferHub/CallOptionalReturn.sol:12",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:432",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:578",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1285",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:589"
    ],
    "claim": "`_callOptionalReturn()` only reverts when the low-level call itself fails. If a token call succeeds but returns `false`, the helper just returns `false`; all callers ignore that return value and continue as if the transfer succeeded.",
    "impact": "For any listed token that signals transfer failure by returning `false`, users can be credited for deposits, repayments, or liquidation paybacks without actually transferring funds. This can lead to unbacked collateral, debt erasure without repayment, and liquidation theft. Outbound flows can also burn shares/debt without actually paying the user.",
    "paths": [
      "Call `depositExactAmount()` or `solelyDeposit()` with a token whose `transferFrom` returns `false`.",
      "Protocol accounting is updated before/without a revert, so the attacker receives shares/collateral credit without funding the pool.",
      "Use the credited position to borrow healthy assets from other pools.",
      "The same bug lets `paybackExactAmount()`, `paybackExactShares()`, and `_coreLiquidation()` accept unpaid inbound transfers as successful debt repayment."
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "Low-liquidity liquidation credits seized shares to the liquidator but records the token under the victim NFT",
    "locations": [
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:493",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:499",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:634"
    ],
    "claim": "When a liquidation wants more collateral than the pool can currently pay out, `_withdrawOrAllocateSharesLiquidation()` moves the residual lending shares to `_nftIdLiquidator`, but then calls `_addPositionTokenData()` with `_nftId` instead of `_nftIdLiquidator`. The liquidator's new lending entry is therefore missing from `positionLendTokenData`, while the victim keeps the token in its list.",
    "impact": "Seized collateral can become partially stranded or invisible to later bookkeeping/security logic. When the liquidator later empties that position, `_removePositionData()` may operate on a token that is not actually present in their token list and can pop/corrupt an unrelated entry. This can break withdrawals and collateral accounting after liquidations in low-liquidity pools.",
    "paths": [
      "Liquidate a position where the desired receive token has insufficient pool liquidity.",
      "Protocol transfers `shareDifference` to `_nftIdLiquidator`.",
      "Bookkeeping adds the token to the victim's `positionLendTokenData` instead of the liquidator's.",
      "Later liquidator actions on that seized asset operate with inconsistent token arrays and can strand or corrupt collateral bookkeeping."
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "low",
    "title": "Position token removal uses a `uint8` index and breaks once a position tracks more than 255 assets",
    "locations": [
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:634",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:657"
    ],
    "claim": "`_removePositionData()` iterates over a dynamic token array with `uint8 i` under `unchecked` increment. If a position ever holds more than 255 token entries, the counter wraps to zero and the loop can no longer safely reach later indices.",
    "impact": "Positions with very large token sets can become impossible to clean up correctly. Withdrawals, repayments, or liquidations that need to remove later entries may run out of gas or mis-handle bookkeeping, creating a permanent denial of service for affected positions.",
    "paths": [
      "Create or accumulate a position with at least 256 tracked lending/borrow tokens.",
      "Trigger any flow that calls `_removePositionData()` for an entry beyond the first 255 slots.",
      "The `uint8` iterator wraps, preventing reliable removal and bricking the cleanup path."
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "low",
    "title": "Isolation-pool registration toggles position locks without any local ownership/security check",
    "locations": [
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1479",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/InterfaceHub/IWiseSecurity.sol:187"
    ],
    "claim": "`setRegistrationIsolationPool()` only checks that `msg.sender` is a verified isolation pool, then writes `positionLocked[_nftId]` directly. Unlike the rest of the system, it performs no ownership check and never calls the apparently intended `WISE_SECURITY.checksRegister()` hook exposed in the interface.",
    "impact": "If a verified isolation-pool contract exposes this path too broadly, is integrated incorrectly, or is compromised, arbitrary user positions can be locked or unlocked. That can freeze users out of deposits/withdrawals/paybacks, or break isolation assumptions by clearing locks unexpectedly.",
    "paths": [
      "A verified isolation-pool contract calls `setRegistrationIsolationPool(victimNft, true)` without a proper upstream ownership check.",
      "Victim position becomes locked and user-facing actions start reverting with `PositionLocked()`.",
      "The same issue can unset a lock unexpectedly if the integration misroutes or is compromised."
    ]
  }
]

```

### Agent: opencode_1
```
Let me read the main contract files to perform the audit.
Let me continue reading the remaining important files:
Let me check the interfaces and remaining files for potential issues:
Now I have a comprehensive understanding of the codebase. Let me compile the security vulnerabilities I've identified:

[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Master can drain excess tokens from any pool via skim function",
    "locations": [
      "WiseLending.sol:108-146"
    ],
    "claim": "The skim() function allows the master address to withdraw any excess tokens sitting in the contract that are not accounted for in the pool's totalPool + totalBareToken calculations.",
    "impact": "If any tokens are accidentally sent to the contract (e.g., from airdrops, mistaken transfers, or from rebasing tokens), the master can drain them. While this may be intended behavior, it gives the master unilateral control over all excess tokens in the contract.",
    "paths": [
      "Attacker tricks users to deposit tokens that have rebasing or airdrop functionality",
      "Master calls skim() to drain accumulated tokens"
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "No emergency stop mechanism - unfixable critical bugs lead to permanent loss",
    "locations": [
      "WiseLendingDeclaration.sol:1-381"
    ],
    "claim": "The protocol has no pause/emergency stop functionality. If a critical vulnerability is discovered, there is no way to halt the protocol to prevent further damage.",
    "impact": "In case of critical bugs (e.g., oracle manipulation, liquidity crisis), users cannot be protected. The protocol remains vulnerable until a migration can be executed.",
    "paths": [
      "Oracle manipulation leads to massive liquidations",
      "Flash loan attack drains liquidity"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "Approval front-running vulnerability - no increaseAllowance function",
    "locations": [
      "WiseLending.sol:280-289"
    ],
    "claim": "The approve() function sets allowance to a specific amount without supporting incremental increases. Users must call set allowance to max, then call decreaseAllowance pattern, but the latter doesn't exist. This forces users to set maximum allowances, creating front-running risk.",
    "impact": "When a user wants to increase their allowance, a MEV bot can front-run the transaction with a higher gas price, set the allowance to max themselves, and drain the user's funds during the allowance window.",
    "paths": [
      "User submits transaction to approve()",
      "MEV bot front-runs with higher gas to set allowance to max",
      "Original transaction fails or succeeds with reduced utility"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "Liquidation executes transfer before verifying success",
    "locations": [
      "WiseCore.sol:589-600"
    ],
    "claim": "In _coreLiquidation, the payback tokens are transferred from liquidator to contract (line 589-594) and collateral is sent to receiver (line 596-600) without checking return values. Although _safeTransferFrom is used, the exact amount received is not validated.",
    "impact": "If the payback token transfer is partially successful or the collateral transfer fails, the transaction may not properly revert, leading to inconsistent state where user has paid back but didn't receive collateral, or vice versa.",
    "paths": [
      "Liquidator calls liquidatePartiallyFromTokens",
      "Payback token transfer partially succeeds",
      "Collateral transfer fails or is inconsistent"
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "Unchecked payback amount in liquidation allows exact amount mismatch",
    "locations": [
      "WiseCore.sol:589-594"
    ],
    "claim": "The liquidator sends payback tokens via _safeTransferFrom but the contract doesn't verify that exact paybackAmount was received. If the token has transfer fees or rounding issues, less may be received.",
    "impact": "If a token charges transfer fees, the liquidation could complete with less payback than required, potentially leaving the position in an invalid state or causing financial loss to the protocol.",
    "paths": [
      "Liquidator uses fee-on-transfer token for payback",
      "Contract receives less than paybackAmount",
      "Position state becomes inconsistent"
    ]
  },
  {
    "id": "F-006",
    "severity": "High",
    "confidence": "high",
    "title": "Oracle price manipulation leading to incorrect liquidations",
    "locations": [
      "WiseCore.sol:545-565",
      "WiseLendingDeclaration.sol:256-258"
    ],
    "claim": "The protocol relies on external oracles for price feeds. The only check is chainLinkIsDead() which checks if oracle is dead, but doesn't verify price freshness or detect manipulation. Oracle prices can be delayed or manipulated.",
    "impact": "Attackers can manipulate oracle prices to trigger incorrect liquidations of healthy positions or prevent legitimate liquidations of unhealthy positions, leading to protocol insolvency or user fund loss.",
    "paths": [
      "Attacker manipulates Chainlink price feed through large trades or flash loans",
      "Healthy positions are incorrectly liquidated",
      "Or unhealthy positions avoid liquidation"
    ]
  },
  {
    "id": "F-007",
    "severity": "High",
    "confidence": "medium",
    "title": "AaveHub and IsolationPool can bypass all security checks",
    "locations": [
      "WiseLowLevelHelper.sol:393-409"
    ],
    "claim": "The _byPassCase() function allows AAVE_HUB_ADDRESS and verifiedIsolationPool to bypass critical security checks including position lock checks, reentrancy guards, and security validations.",
    "impact": "If AaveHub or any verified IsolationPool is compromised, the attacker can bypass all security checks and manipulate any user's positions or drain pool funds.",
    "paths": [
      "AaveHub contract is upgraded with malicious code",
      "IsolationPool is verified then exploited",
      "Attacker bypasses all security checks"
    ]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Share price manipulation via large deposits/withdrawals",
    "locations": [
      "WiseLending.sol:68-89",
      "WiseCore.sol:51-108"
    ],
    "claim": "The syncPool modifier updates pool state before and after operations, but large single transactions can still manipulate share prices significantly, especially in low-liquidity pools.",
    "impact": "Attackers with large capital can manipulate share prices in small pools to gain unfair advantages, steal from other depositors, or cause insolvency.",
    "paths": [
      "Attacker deposits large amount in low-liquidity pool",
      "Share price changes significantly",
      "Attacker withdraws at manipulated price"
    ]
  },
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Rounding up in paybackAmount causes users to overpay",
    "locations": [
      "MainHelper.sol:115-131"
    ],
    "claim": "The paybackAmount function uses ceiling division (adds 1 if remainder exists), meaning users may pay more than their actual debt when paying back loans.",
    "impact": "Users lose a small amount due to rounding up on every payback. Over many transactions, this creates累积 loss for borrowers and profit for protocol.",
    "paths": [
      "User calls paybackExactAmount with exact debt",
      "paybackAmount rounds up",
      "User pays slightly more than needed"
    ]
  },
  {
    "id": "F-010",
    "severity": "Medium",
    "confidence": "high",
    "title": "Missing zero address validation in setSecurity allows setting zero address",
    "locations": [
      "WiseLendingDeclaration.sol:137-158"
    ],
    "claim": "The setSecurity function allows master to set WISE_SECURITY to address(0) after initial setup (no check after first set), and the WISE_SECURITY is marked as public allowing external reads but no validation on updates.",
    "impact": "If WISE_SECURITY is set to zero address, all security checks will fail, potentially locking users out of their funds or allowing unauthorized operations.",
    "paths": [
      "Master accidentally calls setSecurity with zero address",
      "All security-dependent functions revert or behave unexpectedly"
    ]
  },
  {
    "id": "F-011",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Missing validation on collateral factor upper bound in createPool",
    "locations": [
      "PoolManager.sol:143-238"
    ],
    "claim": "The createPool function sets collateralFactor from pool creation params but doesn't validate it's within safe bounds. The check in setPoolParameters only happens when updating, not during initial pool creation.",
    "impact": "Pools created with collateralFactor > 100% (though unlikely as _params.poolCollFactor is validated in setPoolParameters) could cause unexpected behavior, but more critically the missing validation on initial creation could lead to risky pools.",
    "paths": [
      "Pool is created with excessive collateralFactor",
      "Users borrow against over-collateralized position",
      "Liquidation logic fails due to incorrect calculations"
    ]
  },
  {
    "id": "F-012",
    "severity": "Medium",
    "confidence": "low",
    "title": "Position NFT ID not validated - possible array out of bounds",
    "locations": [
      "WiseLendingDeclaration.sol:335-337"
    ],
    "claim": "User data mappings use uint256 as NFT ID without validation that the NFT actually exists or belongs to the caller. Functions like userLendingData, userBorrowShares, pureCollateralAmount don't verify NFT ownership.",
    "impact": "Users could interact with non-existent NFT IDs, causing unnecessary state writes or potential array issues. While mappings don't overflow, gas could be wasted and state could be polluted.",
    "paths": [
      "User calls functions with non-existent NFT ID",
      "State is written to empty positions",
      "Gas is wasted, state is polluted"
    ]
  },
  {
    "id": "F-013",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Flash loan attack vector on liquidation rewards",
    "locations": [
      "WiseLending.sol:1346-1401"
    ],
    "claim": "The liquidation function calculates rewards based on oracle prices without any slippage protection or TWAP (time-weighted average price) validation. Flash loans can be used to manipulate prices at the moment of liquidation.",
    "impact": "Attackers can use flash loans to manipulate token prices, maximize liquidation rewards, and drain value from the protocol or victim positions.",
    "paths": [
      "Attacker takes flash loan",
      "Manipulates oracle prices through large trades",
      "Executes liquidation with max rewards",
      "Repays flash loan"
    ]
  },
  {
    "id": "F-014",
    "severity": "Low",
    "confidence": "medium",
    "title": "Unchecked return value in receive function",
    "locations": [
      "WiseLending.sol:49-61"
    ],
    "claim": "The receive() function sends ETH to master via _sendValue but doesn't handle the case where _sendValue might fail silently or incompletely.",
    "impact": "If _sendValue fails, the ETH gets stuck in the contract. While the function checks success, if the recipient is a contract that reverts, the ETH is locked forever.",
    "paths": [
      "ETH is sent to contract via receive()",
      "Master contract is a contract that reverts on receive",
      "ETH becomes stuck in contract"
    ]
  },
  {
    "id": "F-015",
    "severity": "Low",
    "confidence": "low",
    "title": "Potential integer overflow in fee share calculation",
    "locations": [
      "MainHelper.sol:521-523"
    ],
    "claim": "Fee shares calculation: feeAmount * lendingPoolData[_poolToken].totalDepositShares / (lendingPoolData[_poolToken].pseudoTotalPool - feeAmount) could overflow on the multiplication if both values are near max uint256.",
    "impact": "If the multiplication overflows, the calculation would wrap around, potentially causing incorrect fee distribution or allowing attackers to claim excessive fees.",
    "paths": [
      "Pool grows to extremely large values",
      "Fee calculation multiplication overflows",
      "Fee shares calculated incorrectly"
    ]
  },
  {
    "id": "F-016",
    "severity": "Low",
    "confidence": "medium",
    "title": "No timelock on master actions - immediate effect",
    "locations": [
      "PoolManager.sol:25-78"
    ],
    "claim": "All master-controlled functions (setParamsLASA, setPoolParameters, createPool, etc.) take immediate effect without any timelock or delay.",
    "impact": "If master private key is compromised or master acts maliciously, users have no time to react. Funds can be drained or parameters changed instantly.",
    "paths": [
      "Master private key compromised",
      "Attacker changes pool parameters to steal funds",
      "Users have no time to withdraw"
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
