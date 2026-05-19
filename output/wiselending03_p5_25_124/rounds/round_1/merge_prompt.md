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
    "title": "Transfer-in accounting trusts the requested amount instead of the tokens actually received",
    "locations": [
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:416",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:556",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1255",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1299",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:545",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:720"
    ],
    "claim": "Deposits, solely-deposits, paybacks, and liquidation payback legs all book `_amount` into protocol accounting before or without verifying the balance delta, so fee-on-transfer/deflationary/non-standard ERC20s can mint too many lending shares or extinguish too much debt for too few tokens.",
    "impact": "If such a token is listed, an attacker can overmint claims on the pool, repay debt at a discount, and push losses onto lenders/other borrowers, leading to pool insolvency or direct fund theft.",
    "paths": [
      "depositExactAmount -> _handleDeposit -> _safeTransferFrom",
      "solelyDeposit -> _handleSolelyDeposit -> _safeTransferFrom",
      "paybackExactAmount/paybackExactShares -> _handlePayback -> _safeTransferFrom",
      "_coreLiquidation -> _corePayback -> _safeTransferFrom"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "depositExactAmountETHMint skips pool synchronization and can mint WETH shares at a stale price",
    "locations": [
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:68",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:345",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:383",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:358"
    ],
    "claim": "`depositExactAmountETHMint()` calls `_depositExactAmountETH()` directly instead of going through the `syncPool(WETH_ADDRESS)` modifier used by the normal ETH deposit path, so share minting can use stale `pseudoTotalPool`/borrow accrual data.",
    "impact": "After a period of un-synced interest accrual, an attacker can mint excess WETH lending shares before the pool is updated and later redeem those shares against the properly synced pool, stealing accrued interest from existing lenders.",
    "paths": [
      "depositExactAmountETHMint -> _depositExactAmountETH -> _handleDeposit"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "high",
    "title": "Illiquid liquidation credits shares to the liquidator but records the token under the victim NFT",
    "locations": [
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:437",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:493",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:499",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:634",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:1131"
    ],
    "claim": "When liquidation cannot pay out all collateral in tokens, `_withdrawOrAllocateSharesLiquidation()` moves residual lending shares to `_nftIdLiquidator` but calls `_addPositionTokenData()` with `_nftId`, corrupting the liquidator's position bookkeeping.",
    "impact": "The liquidator's newly received shares may become hidden from position enumeration; later full withdrawals can revert or pop an unrelated token from the liquidator's token list, causing funds to become hard to recover and corrupting later accounting/security flows that rely on the token arrays.",
    "paths": [
      "liquidatePartiallyFromTokens/coreLiquidationIsolationPools -> _coreLiquidation -> _withdrawOrAllocateSharesLiquidation",
      "later withdrawExactAmount/withdrawExactShares -> _removeEmptyLendingData -> _removePositionData"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "low",
    "title": "Isolation-pool liquidations trust caller-supplied payback terms and skip the normal liquidation gate",
    "locations": [
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1406",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1433",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:545",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:720"
    ],
    "claim": "`coreLiquidationIsolationPools()` does not recompute `_paybackAmount` from `_shareAmountToPay`, does not run the normal `checksLiquidation()` path, and forwards both values directly into `_coreLiquidation()`/`_corePayback()`.",
    "impact": "A buggy or malicious verified isolation pool can forgive arbitrary borrower shares for too little payment, or execute liquidations on terms the normal public path would reject, socializing losses onto the main lending pools.",
    "paths": [
      "coreLiquidationIsolationPools -> _coreLiquidation -> _corePayback"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Anyone can dust arbitrary NFTs, and token-removal logic breaks once a position tracks more than 255 tokens",
    "locations": [
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:416",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:556",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseCore.sol:242",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:634",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/MainHelper.sol:657"
    ],
    "claim": "Deposit paths do not require ownership or approval of the target `_nftId`, so anyone can append supported pool tokens to another user's position; meanwhile `_removePositionData()` iterates with a `uint8` index, which wraps once token lists exceed 255 entries.",
    "impact": "A victim position can be griefed by dust deposits across many listed pools. Once the tracked-token count exceeds 255, any full withdrawal/removal path that needs to delete an entry can become non-terminating/out-of-gas, effectively freezing exits for that position.",
    "paths": [
      "attacker depositExactAmount/solelyDeposit into victim NFT across many pools",
      "victim later withdraws fully -> _removeEmptyLendingData/_removePositionData"
    ]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "low",
    "title": "The per-pool allowBorrow flag is stored but never enforced in the audited borrow path",
    "locations": [
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/PoolManager.sol:195",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1040",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1088",
      "0x37e49bf3749513a02fa535f0cbc383796e8107e4/contracts/WiseLending.sol:1134"
    ],
    "claim": "`borrowPoolData[_poolToken].allowBorrow` is initialized at pool creation but is not checked anywhere in the in-scope borrow functions or core borrow logic.",
    "impact": "If the out-of-scope security module does not separately enforce this flag, pools intended to be deposit-only/collateral-only remain borrowable, allowing unintended liquidity drainage from those assets.",
    "paths": [
      "createPool(... allowBorrow = false) -> borrowExactAmount/borrowExactAmountETH/borrowOnBehalfExactAmount"
    ]
  }
]

```

### Agent: opencode_1
```
Now I'll read all the contract files to identify security vulnerabilities. Let me start by reading the main contracts:
Let me continue reading more contracts to find vulnerabilities:
Let me continue reading more contracts:
Let me continue reading more contracts to complete the audit:
Now let me read the remaining files:
Now let me read a few more interface files to fully understand the security checks:
Now I have a good understanding of the contracts. Let me search for any additional critical patterns I may have missed:
Now let me compile all the findings into the required JSON format:
Now I have completed my audit. Based on my thorough analysis of all 17 contract files, I've identified several security vulnerabilities. Let me compile them into the required JSON format:
[
  {
    "id": "F-001",
    "severity": "High",
    "confidence": "high",
    "title": "Reentrancy vulnerability in liquidation due to unsafe external calls",
    "locations": ["WiseCore.sol:589-600"],
    "claim": "The _coreLiquidation function performs external token transfers (_safeTransferFrom and _safeTransfer) after state updates but before the reentrancy guard (sendingProgress) is reset.",
    "impact": "A malicious token could implement a callback in its transfer function to re-enter the liquidation function or other vulnerable functions within the same transaction, potentially manipulating the protocol state or stealing funds.",
    "paths": ["1. Attacker creates a malicious token that implements a hook in transfer()\n2. Attacker triggers liquidation on a victim's position\n3. During _safeTransfer, the malicious token calls back into WiseLending liquidation functions\n4. Attacker exploits the unreset state to manipulate the liquidation for profit"]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Flash loan price manipulation vulnerability in liquidation",
    "locations": ["WiseCore.sol:545-601", "IWiseOracleHub.sol:54-60"],
    "claim": "The liquidation function uses spot prices from the oracle (getTokensInETH) without any TWAP or time-weighted averaging mechanism.",
    "impact": "An attacker can use a flash loan to manipulate the oracle price, trigger a liquidation at an artificially favorable price, and profit from the price manipulation in a single atomic transaction.",
    "paths": ["1. Attacker takes a flash loan\n2. Attacker manipulates the Chainlink or other price feed to create an artificially favorable price\n3. Attacker calls liquidatePartiallyFromTokens to liquidate a position\n4. The protocol uses the manipulated price to calculate collateral to receive\n5. Attacker repays flash loan and keeps profit"]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "Division by zero in share calculation functions",
    "locations": ["MainHelper.sol:39-43", "MainHelper.sol:79-84"],
    "claim": "The calculateLendingShares and calculateBorrowShares functions divide by pseudoTotalPool and pseudoTotalBorrowAmount respectively. If these values become zero, it will cause a division by zero revert.",
    "impact": "When a pool's pseudoTotalPool or pseudoTotalBorrowAmount becomes zero (extreme edge case during sync), users cannot calculate shares and their positions become frozen.",
    "paths": ["1. Pool reaches extreme utilization conditions\n2. pseudoTotalPool or pseudoTotalBorrowAmount becomes 0\n3. Users attempting to deposit/borrow receive division by zero error\n4. Position becomes locked"]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "Fee calculation can result in zero shares causing fee loss",
    "locations": ["MainHelper.sol:521-523"],
    "claim": "Fee shares calculation: feeAmount * totalDepositShares / (pseudoTotalPool - feeAmount) can result in zero due to integer truncation, causing protocol fees to be lost.",
    "impact": "When the fee amount is very small relative to pool size, the calculation results in zero shares, meaning those fees are not collected and remain in the pool as excess value.",
    "paths": ["1. Pool has large totalDepositShares and pseudoTotalPool\n2. Fee amount is small relative to pool\n3. Integer division truncates to zero\n4. Protocol loses the fee revenue"]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "medium",
    "title": "Lack of Oracle dead switch - price manipulation via dead oracle",
    "locations": ["WiseCore.sol:256-258", "WiseLendingDeclaration.sol:112-134"],
    "claim": "The chainLinkIsDead check is performed for deposits but not consistently for withdrawals and borrows. A dead oracle could be used to manipulate prices.",
    "impact": "If Chainlink oracle becomes stale or dead for a token, the protocol may use stale prices allowing attackers to steal funds by borrowing against inflated collateral or liquidating at unfair prices.",
    "paths": ["1. Oracle for a token becomes dead/stale\n2. Attacker deposits the token as collateral at last valid price\n3. Price drops significantly but stale price still shows high value\n4. Attacker borrows against this inflated collateral\n5. Attacker defaults, protocol realizes loss"]
  },
  {
    "id": "F-006",
    "severity": "Medium",
    "confidence": "high",
    "title": "Missing access control allows unauthorized position operations",
    "locations": ["WiseLending.sol:279-289", "WiseLendingDeclaration.sol:340"],
    "claim": "The approve function does not verify that the caller owns the position NFT or has approval, allowing anyone to set allowances for any position.",
    "impact": "An attacker can set allowances on another user's position, potentially leading to unauthorized withdrawals or manipulation of the position's collateral.",
    "paths": ["1. Attacker calls approve(spender, poolToken, amount) on any position\n2. The allowance mapping is updated for an arbitrary address\n3. This could confuse users or lead to social engineering attacks"]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Inconsistent position lock checks across functions",
    "locations": ["WiseLending.sol:313-337", "WiseCore.sol:199-215"],
    "claim": "The unCollateralizeDeposit function does not call _checkPositionLocked while other sensitive functions do, creating an inconsistent security model.",
    "impact": "A position that is locked for power farms could still have its collateral uncollateralized, potentially breaking the isolation pool assumptions.",
    "paths": ["1. Position is locked for power farm/isolation pool\n2. User calls unCollateralizeDeposit\n3. Function bypasses position lock check\n4. Collateral state is modified unexpectedly"]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Race condition in _reduceAllowance allows double spending of allowance",
    "locations": ["WiseLending.sol:924-943"],
    "claim": "The _reduceAllowance function checks if the spender is approved OR calculates remaining allowance. This logic may allow double spending of allowance in certain edge cases.",
    "impact": "A whitelisted caller may be able to withdraw more than the approved amount due to the complex allowance reduction logic.",
    "paths": ["1. User sets allowance for whitelisted contract\n2. Multiple onBehalf calls in same transaction\n3. Allowance check and reduction not atomic\n4. Attractor withdraws more than approved"]
  },
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "medium",
    "title": "No slippage protection in liquidation",
    "locations": ["WiseCore.sol:545-601", "WiseLending.sol:1346-1401"],
    "claim": "The liquidation function does not provide minimum receive amount parameters, allowing front-running and MEV extraction.",
    "impact": "Liquidators can be front-run by validators or bots who extract the liquidation reward, leading to reduced protocol efficiency and potential griefing.",
    "paths": ["1. Liquidator submits transaction to liquidate\n2. Validator/MEV bot sees the transaction in mempool\n3. Bot front-runs with higher gas to capture the liquidation\n4. Original liquidator's transaction fails or gets reduced profit"]
  },
  {
    "id": "F-010",
    "severity": "Medium",
    "confidence": "low",
    "title": "LASA algorithm can be manipulated via deposit/withdraw timing",
    "locations": ["MainHelper.sol:887-917", "PoolManager.sol:25-78"],
    "claim": "The LASA (Lending Automated Scaling Algorithm) uses totalDepositShares which can be manipulated by sandwiching operations before the 3-hour threshold.",
    "impact": "An attacker can manipulate the bonding curve parameters by timing deposits and withdrawals to exploit the algorithm's decision-making process.",
    "paths": ["1. Attacker monitors pending LASA update\n2. Sandwiches deposits/withdrawals to influence totalDepositShares\n3. LASA algorithm adjusts pole based on manipulated values\n4. Attacker profits from altered interest rates"]
  },
  {
    "id": "F-011",
    "severity": "Low",
    "confidence": "high",
    "title": "Immutable WISE_SECURITY after initial setup - no upgrade path",
    "locations": ["WiseLendingDeclaration.sol:137-158"],
    "claim": "The setSecurity function can only be called once and cannot be changed afterwards. If security module has critical bugs, there is no recovery path.",
    "impact": "Any bug in the WISE_SECURITY contract becomes permanent, potentially leading to permanent fund lock or protocol failure with no possible fix except contract migration.",
    "paths": ["1. setSecurity is called with a buggy security contract\n2. Critical security checks fail or pass incorrectly\n3. Protocol becomes unusable or funds become locked\n4. No way to fix without new deployment"]
  },
  {
    "id": "F-012",
    "severity": "Low",
    "confidence": "medium",
    "title": "Timestamp dependence in LASA algorithm",
    "locations": ["MainHelper.sol:879", "MainHelper.sol:1075-1092"],
    "claim": "The LASA algorithm uses block.timestamp which can be manipulated by miners within limits.",
    "impact": "Miner can slightly influence the timing of LASA adjustments by manipulating block timestamp within the 900-second rule, potentially gaining marginal advantage.",
    "paths": ["1. Miner manipulates block.timestamp\n2. LASA delta calculation affected\n3. Pole value shifted slightly\n4. Miner profits from interest rate difference"]
  },
  {
    "id": "F-013",
    "severity": "Low",
    "confidence": "medium",
    "title": "Pure collateral can be liquidated without health check",
    "locations": ["WiseCore.sol:514-539", "WiseLendingDeclaration.sol:336"],
    "claim": "Pure collateral (solely deposited funds) can be withdrawn or liquidated without the same health checks as regular collateral.",
    "impact": "Users' pure collateral may be liquidated even when their position is technically healthy, leading to unexpected loss of funds.",
    "paths": ["1. User has pure collateral in position\n2. Liquidator calls liquidation\n3. Pure collateral is calculated without full health check\n4. User loses collateral unexpectedly"]
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
