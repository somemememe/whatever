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
    "title": "Exact-amount borrows and withdrawals can round to zero shares and bypass accounting",
    "locations": [
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:31",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:68",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseCore.sol:308",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseCore.sol:341",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:423",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:520",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:688",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:841",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:891",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:940"
    ],
    "claim": "The exact-amount paths derive shares with floor division, but neither the borrow nor withdraw flows require the computed share amount to be nonzero. Once `pseudoTotalBorrowAmount > totalBorrowShares` or `pseudoTotalPool > totalDepositShares`, a small exact-amount operation can create/consume 0 shares while still moving real pool balances.",
    "impact": "A borrower can repeatedly take small loans that never increase `userBorrowShares`, draining liquidity without accruing debt. Likewise, a lender can repeatedly withdraw small amounts that burn no lending shares, stealing value from other lenders and potentially emptying the pool.",
    "paths": [
      "Wait until a pool's share price exceeds 1 unit (`pseudoTotalBorrowAmount / totalBorrowShares > 1` or `pseudoTotalPool / totalDepositShares > 1`).",
      "Call `borrowExactAmount`, `borrowExactAmountETH`, or `borrowOnBehalfExactAmount` with an `_amount` that makes `calculateBorrowShares(...) == 0`.",
      "Call `withdrawExactAmount`, `withdrawExactAmountETH`, or `withdrawOnBehalfExactAmount` with an `_amount` that makes `calculateLendingShares(...) == 0`."
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Repeated syncs can re-accrue the same interest window whenever fee rounding yields zero",
    "locations": [
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:386",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:428",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:447"
    ],
    "claim": "In `_updatePseudoTotalAmounts`, if `amountInterest > 0` but `feeAmount == 0`, the function increases `pseudoTotalBorrowAmount` and `pseudoTotalPool` and then returns without updating `timeStamp`. The next sync therefore charges interest for the same elapsed seconds again.",
    "impact": "Anyone can loop `syncManually` or other `syncPool` entrypoints to manufacture pseudo-interest on small/quiet pools, inflating debts and lender balances without corresponding assets. This distorts solvency and collateral accounting and can enable overborrowing or forced liquidations against fictitious value.",
    "paths": [
      "Reach a state where one accrual step produces `amountInterest > 0` and `feeAmount == 0`.",
      "Call `syncManually(pool)` repeatedly from a helper contract in one transaction; each call reuses the same old `timeStamp` and re-applies the same accrual interval."
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "depositExactAmountETHMint bypasses WETH pool synchronization and over-mints shares",
    "locations": [
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:202",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:215",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:246"
    ],
    "claim": "The normal ETH deposit path uses `syncPool(WETH_ADDRESS)` before calculating shares, but `depositExactAmountETHMint()` calls the internal `_depositExactAmountETH()` directly and skips synchronization entirely. Any unaccrued interest or cleanup in the WETH pool is therefore ignored when minting shares.",
    "impact": "When the WETH pool has pending accrual, the mint shortcut issues too many lending shares. An attacker can mint through `depositExactAmountETHMint`, then use a later synced action to redeem or borrow against the excess shares, diluting existing lenders.",
    "paths": [
      "Let the WETH pool accumulate pending interest.",
      "Call `depositExactAmountETHMint()` instead of `depositExactAmountETH()`.",
      "After a synced interaction updates the pool, redeem the over-minted shares or use them as inflated collateral."
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "Accounting assumes full token transfers and breaks for fee-on-transfer or deflationary assets",
    "locations": [
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:279",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:301",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:386",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:401",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:1060",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:1087",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:1101",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:1128",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseCore.sol:731",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseCore.sol:749"
    ],
    "claim": "Deposits, solely deposits, repayments, and liquidations all update internal pool accounting using the requested `_amount`, but never verify how many tokens actually arrived. The code therefore assumes all listed assets are strict ERC20s with no transfer tax, burn, or negative rebase semantics.",
    "impact": "If a listed token transfers less than `_amount`, users can mint excess shares/collateral on deposit or repay/liquidate positions while underpaying the protocol. The resulting shortfall is socialized to the pool and can render it insolvent.",
    "paths": [
      "List or interact with a fee-on-transfer / deflationary pool token.",
      "Use `depositExactAmount` or `solelyDeposit` to get credited for more than the contract receives.",
      "Use `paybackExactAmount`, `paybackExactShares`, or liquidation to reduce debt by the nominal amount while sending less value in."
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "Illiquid liquidation payouts register the token on the debtor NFT instead of the liquidator NFT",
    "locations": [
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseCore.sol:647",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseCore.sol:653",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:537",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:1020"
    ],
    "claim": "When liquidation cannot pay out all collateral in cash, `_withdrawOrAllocateSharesLiquidation()` credits `shareDifference` to `_nftIdLiquidator` but mistakenly calls `_addPositionTokenData()` with the debtor `_nftId`. The liquidator receives shares without the corresponding token entry in their NFT bookkeeping.",
    "impact": "The liquidator's share-based payout can become hard to recover. On a fresh liquidator NFT with no lending-token entries, fully withdrawing the credited shares later reverts during cleanup because `_removePositionData()` is called on an empty array.",
    "paths": [
      "Liquidate a position where `cashoutAmount > totalPool`, so part of the reward is allocated as lending shares.",
      "Use a liquidator NFT that does not already track the received token.",
      "Attempt to fully withdraw the credited shares and hit the inconsistent-token-list cleanup path."
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Position token arrays hard-fail once a position accumulates more than 255 entries",
    "locations": [
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:353",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:361",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:537",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/MainHelper.sol:560",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseCore.sol:512",
      "0x84524baa1951247b3a2617a843e6ece915bb9674/contracts/WiseLending.sol:1142"
    ],
    "claim": "Both `_prepareTokens()` and `_removePositionData()` use `uint8` loop counters. Once a borrow/lending token array reaches 256 entries, the counter overflows and the loop reverts. `paybackExactLendingShares()` also never removes emptied lending tokens, so token lists can grow monotonically over time.",
    "impact": "An affected NFT can become impossible to sync, withdraw, repay, decollateralize, or liquidate, effectively locking the whole position. The stale-entry leak makes the DOS increasingly realistic as more pools are added over the protocol's lifetime.",
    "paths": [
      "Accumulate 256 distinct lending/borrow token entries on one NFT.",
      "Alternatively, cycle through many pools via `paybackExactLendingShares()` so emptied lending entries are never removed.",
      "Any later path that calls `_prepareTokens()` or `_removePositionData()` reverts permanently."
    ]
  }
]

```

### Agent: opencode_1
```
Let me read all the contract files to analyze them for security vulnerabilities.
Now let me read more files in parallel to analyze for vulnerabilities:
Let me read the remaining files to complete my analysis:
Based on my comprehensive security audit of the WiseLending protocol contracts, I've identified several vulnerabilities. Let me provide the findings in the required JSON format:

[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Unverified setSecurity allows arbitrary contract assignment",
    "locations": ["WiseLendingDeclaration.sol:154-169"],
    "claim": "The setSecurity function allows the master to set any address as the security contract without any validation or timelock.",
    "impact": "The master can hijack critical protocol settings by pointing WISE_SECURITY to a malicious contract, allowing redirection of FEE_MANAGER and AAVE_HUB, potentially leading to complete fund theft.",
    "paths": ["Master calls setSecurity() with malicious security contract address"]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Liquidation state inconsistency - token transfer after state update",
    "locations": ["WiseCore.sol:731-760", "WiseLending.sol:1249-1254"],
    "claim": "In liquidation, _corePayback() is called to update borrow state BEFORE the actual token transfer via _safeTransferFrom. If the transfer fails, state modifications are already applied.",
    "impact": "If the liquidator's token transfer fails (insufficient balance, blacklisted, or non-standard token), the borrow position is reduced but the liquidator doesn't receive collateral, causing permanent state inconsistency.",
    "paths": ["Liquidator calls liquidatePartiallyFromTokens with insufficient balance or blacklisted token"]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "Division by zero in fee share calculation",
    "locations": ["MainHelper.sol:432-434"],
    "claim": "The fee shares calculation divides by (getPseudoTotalPool(_poolToken) - feeAmount), which can be zero when feeAmount equals pseudoTotalPool exactly.",
    "impact": "When the accumulated interest exactly equals the pseudo total pool, the division will cause a revert, blocking all pool operations including deposits, withdrawals, borrows, and liquidations.",
    "paths": ["Interest accumulation reaches a point where feeAmount equals pseudoTotalPool"]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "high",
    "title": "Missing reentrancy protection in receive function",
    "locations": ["WiseLending.sol:49-60"],
    "claim": "The receive() function lacks a reentrancy guard and performs an external call (payable(master).transfer) without protection.",
    "impact": "A malicious contract calling WiseLending can trigger a reentrancy attack. While the current implementation only transfers to master, a sophisticated attack could exploit this pattern. Additionally, this allows any contract to force ETH into the protocol.",
    "paths": ["Attacker deploys malicious contract that calls WiseLending receive function"]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "Missing zero address validation in approve function",
    "locations": ["WiseLending.sol:131-147"],
    "claim": "The approve function does not validate that _spender is not the zero address.",
    "impact": "Users may accidentally approve the zero address, rendering their allowance useless. This can lead to failed transactions when trying to use the allowance.",
    "paths": ["User accidentally calls approve with zero address as spender"]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "medium",
    "title": "No emergency stop mechanism",
    "locations": ["All contracts"],
    "claim": "There is no pausable mechanism to halt the protocol in case of critical vulnerability discovery.",
    "impact": "In case of a critical bug or exploit, the team has no way to stop the protocol to prevent further fund loss. This could lead to unlimited exploitation window.",
    "paths": ["Critical vulnerability discovered - no way to pause protocol"]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "low",
    "title": "Liquidation transaction can be delayed indefinitely",
    "locations": ["WiseLending.sol:1213-1261"],
    "claim": "The liquidation functions have no deadline or expiration, allowing liquidators to hold transactions in mempool indefinitely.",
    "impact": "Liquidators can grief the protocol by submitting liquidation transactions with low gas and holding them, potentially affecting price oracle freshness and pool states.",
    "paths": ["Liquidator submits liquidation with low gas and delays execution"]
  },
  {
    "id": "F-008",
    "severity": "Low",
    "confidence": "high",
    "title": "Collateral factor allows 100%",
    "locations": ["PoolManager.sol:89-91"],
    "claim": "The collateral factor check uses > instead of >=, allowing a collateral factor of exactly 100% (1e18).",
    "impact": "A position with 100% collateral factor is mathematically equivalent to the borrowed amount, which can lead to immediate liquidation with any price movement. Users may inadvertently set dangerous positions.",
    "paths": ["Master sets collateralFactor to 1e18 via setPoolParameters"]
  },
  {
    "id": "F-009",
    "severity": "Low",
    "confidence": "medium",
    "title": "Missing event emissions for critical functions",
    "locations": ["WiseLowLevelHelper.sol:464-472"],
    "claim": "The setPoolFee function modifies the pool fee but does not emit any event.",
    "impact": "Off-chain monitoring and indexing becomes difficult. Important protocol parameter changes cannot be easily tracked by users or external systems.",
    "paths": ["Fee manager calls setPoolFee"]
  },
  {
    "id": "F-010",
    "severity": "Low",
    "confidence": "high",
    "title": "Renounce ownership is permanent with no recovery",
    "locations": ["OwnableMaster.sol:81-87"],
    "claim": "The renounceOwnership function sets master to ZERO_ADDRESS with no recovery mechanism.",
    "impact": "If the master accidentally calls renounceOwnership, the contract becomes permanently non-upgradeable and cannot be fixed if bugs are found. All future upgrades are impossible.",
    "paths": ["Master accidentally calls renounceOwnership"]
  },
  {
    "id": "F-011",
    "severity": "Low",
    "confidence": "low",
    "title": "Fee manager NFT ID assumption",
    "locations": ["WiseLendingDeclaration.sol:208", "MainHelper.sol:436-445"],
    "claim": "The protocol assumes FEE_MANAGER_NFT = 0 is the correct ID for the fee manager position, with no validation in constructor or setSecurity.",
    "impact": "If the PositionNFT contract uses a different ID for the fee manager or has a non-standard implementation, fee distribution will fail silently, causing financial loss.",
    "paths": ["PositionNFT contract uses different ID for fee manager"]
  },
  {
    "id": "F-012",
    "severity": "Medium",
    "confidence": "low",
    "title": "Potential storage collision with isolated pools",
    "locations": ["WiseLending.sol:1318-1335", "WiseLendingDeclaration.sol:298-300"],
    "claim": "The positionLocked mapping is used both for actual position locking (power farm security) and isolation pool registration without clear separation.",
    "impact": "Misuse or confusion between these two different purposes could lead to positions being incorrectly locked or isolation pool registration being overwritten.",
    "paths": ["Isolation pool and power farm both try to modify positionLocked"]
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
