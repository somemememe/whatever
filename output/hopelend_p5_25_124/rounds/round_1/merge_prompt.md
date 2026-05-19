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
    "confidence": "medium",
    "title": "Flashloan debt opening uses a stale eMode snapshot after arbitrary callback state changes",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/pool/Pool.sol:348",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/pool/Pool.sol:361",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/FlashLoanLogic.sol:103",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/FlashLoanLogic.sol:136",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/FlashLoanLogic.sol:152"
    ],
    "claim": "Pool.flashLoan snapshots _usersEModeCategory[onBehalfOf] before calling the receiver, but FlashLoanLogic later opens debt after executeOperation returns while still reusing that stale snapshot. A receiver can change its own stored eMode during the callback, so the final borrow is validated against the old category rather than the post-callback category actually left in storage.",
    "impact": "A receiver can end the transaction with debt sized for a more favorable eMode than the one actually active on the account, leaving the position immediately undercollateralized and pushing liquidation shortfall risk onto lenders.",
    "paths": [
      "A receiver contract with collateral enters a favorable eMode category and calls flashLoan with interestRateModes[i] != NONE on behalf of itself.",
      "Inside executeOperation it calls setUserEMode(0) or another less favorable category while its pre-existing position still satisfies health-factor checks.",
      "After the callback, FlashLoanLogic executes BorrowLogic with the stale flashParams.userEModeCategory captured before the callback.",
      "The transaction ends with storage showing the weaker category, but with debt that was only valid under the earlier category."
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "medium",
    "title": "Isolation debt ceilings can be bypassed by splitting borrows below the 0.01-token accounting unit",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/ValidationLogic.sol:196",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/BorrowLogic.sol:137"
    ],
    "claim": "Isolation-mode debt is tracked as floor(amount * 10^2 / 10^decimals). Any borrow smaller than one debt-ceiling unit rounds to zero in both validation and state updates, so repeated small borrows do not increase isolationModeTotalDebt and never count against the configured ceiling.",
    "impact": "The protocol's main isolation-mode solvency guard can be bypassed over repeated calls, allowing materially more isolated debt than governance intended and enlarging the bad-debt blast radius if the isolated collateral fails.",
    "paths": [
      "A user supplies an isolated collateral asset.",
      "The user repeatedly borrows a borrowable-in-isolation asset in chunks smaller than 10^(decimals-2).",
      "Each chunk passes the DEBT_CEILING_EXCEEDED check because the tracked increment rounds down to zero.",
      "The aggregate borrowed amount exceeds the configured ceiling while isolationModeTotalDebt stays artificially low."
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "high",
    "title": "Reserve deletion ignores outstanding unbacked bridge liabilities",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/BridgeLogic.sol:73",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/ValidationLogic.sol:628",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/ValidationLogic.sol:640"
    ],
    "claim": "Bridge minting increases reserve.unbacked, but validateDropReserve only checks token total supplies and accruedToTreasury. It never requires reserve.unbacked to be zero, so a reserve can be dropped while the pool is still owed bridged liquidity.",
    "impact": "Deleting the reserve can erase the accounting needed to back outstanding bridge debt, converting what should be a temporary unbacked hole into permanent market insolvency.",
    "paths": [
      "A bridge mints unbacked hTokens for a reserve.",
      "Those hTokens are withdrawn against existing pool liquidity until hToken totalSupply returns to zero.",
      "The configurator calls dropReserve because validateDropReserve sees no hToken supply and no debt token supply.",
      "Reserve storage is deleted even though reserve.unbacked remains non-zero, preventing later settlement through backUnbacked."
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "Any account can frontrun proxy initialization",
    "locations": [
      "0x53fbcada1201a465740f2d64ecdf6fac425f9030/lend-core/contracts/dependencies/openzeppelin/upgradeability/InitializableUpgradeabilityProxy.sol:20",
      "0x53fbcada1201a465740f2d64ecdf6fac425f9030/lend-core/contracts/dependencies/openzeppelin/upgradeability/InitializableUpgradeabilityProxy.sol:23",
      "0x53fbcada1201a465740f2d64ecdf6fac425f9030/lend-core/contracts/dependencies/openzeppelin/upgradeability/InitializableUpgradeabilityProxy.sol:25"
    ],
    "claim": "InitializableUpgradeabilityProxy.initialize is public and has no admin/authentication check. The first caller of a freshly deployed proxy chooses both the implementation address and arbitrary delegatecall initialization payload.",
    "impact": "If deployment and initialization are not atomic, an attacker can seize the proxy's initial implementation/state, poison storage through delegatecall, and potentially drain or permanently corrupt the proxied system before the intended admin recovers it.",
    "paths": [
      "A new proxy is deployed with an empty implementation slot.",
      "Before the trusted deployer initializes it, an attacker calls initialize with a malicious implementation and crafted initialization calldata.",
      "The proxy stores the attacker-controlled implementation and delegatecalls attacker-controlled code in proxy storage."
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "feeToVault is never actually paid despite emitting vault fee events",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/PoolLogic.sol:117",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/PoolLogic.sol:119",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/PoolLogic.sol:128"
    ],
    "claim": "executeMintToTreasury always mints the full accrued amount to the reserve treasury, then only subtracts amountToVault from a local variable and emits CollectedToVault. The feeToVault address is never used to mint or transfer any tokens.",
    "impact": "The configured ecosystem vault share is silently diverted or stranded in the treasury instead of reaching the vault, and emitted fee events misstate the real on-chain distribution.",
    "paths": [
      "The pool admin sets a non-zero feeToVault address and feeToVaultPercent.",
      "mintToTreasury mints the full amount to the treasury via hToken.mintToTreasury(amountToMint, normalizedIncome).",
      "The function emits CollectedToVault without transferring or minting anything to feeToVault."
    ]
  },
  {
    "id": "F-006",
    "severity": "Low",
    "confidence": "high",
    "title": "Unchecked flashloan premium split can brick flashloan repayment",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/pool/Pool.sol:597",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/pool/Pool.sol:603",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/FlashLoanLogic.sol:229",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/FlashLoanLogic.sol:230"
    ],
    "claim": "updateFlashloanPremiums does not enforce flashLoanPremiumToProtocol <= flashLoanPremiumTotal. If governance configures an invalid split, _handleFlashLoanRepayment underflows when computing premiumToLP.",
    "impact": "Normal flashloan repayment paths revert, disabling flashloans until the configuration is manually repaired.",
    "paths": [
      "The configurator sets flashLoanPremiumToProtocol above flashLoanPremiumTotal.",
      "A user calls flashLoan or flashLoanSimple and takes the repayment path.",
      "FlashLoanLogic computes premiumToLP = totalPremium - premiumToProtocol and reverts on underflow."
    ]
  }
]

```

### Agent: opencode_1
```
Let me also examine more key files:
Now I will review the DataTypes and the proxy contracts:
Let me examine a few more critical files:
Now I have sufficient information to compile my findings. Let me produce the JSON output with all the security vulnerabilities I've identified:

[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "No Access Control on rescueTokens Function",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/PoolLogic.sol:80-86"
    ],
    "claim": "The executeRescueTokens function has no access control, allowing anyone to rescue any token from the Pool contract.",
    "impact": "A malicious actor could drain all tokens held in the Pool contract, including user funds held as liquidity.",
    "paths": [
      "Call rescueTokens with any token address and any recipient address"
    ]
  },
  {
    "id": "F-002",
    "severity": "Critical",
    "confidence": "high",
    "title": "Unchecked Liquidation Bonus Allows Protocol Loss",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/LiquidationLogic.sol:527-533",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol:122-131"
    ],
    "claim": "The liquidation bonus can be set up to 65535 (655.35%) with no upper bound validation in the protocol. Additionally, when combined with liquidation protocol fee, the total deduction can exceed 100%.",
    "impact": "Liquidators may receive more collateral than the debt they repay, causing protocol losses. Users may lose all their collateral in liquidation.",
    "paths": [
      "Configure reserve with high liquidation bonus (>100%)",
      "Liquidate positions where bonus + protocol fee exceeds collateral value"
    ]
  },
  {
    "id": "F-003",
    "severity": "Critical",
    "confidence": "medium",
    "title": "No Health Factor Validation When Switching eMode from Category 0",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/EModeLogic.sol:42-75"
    ],
    "claim": "When a user switches from eMode category 0 (default) to a non-zero category, there is no health factor validation. The validation only runs when prevCategoryId != 0.",
    "impact": "Users can switch to an eMode category with lower LTV/liquidation threshold, potentially dropping their health factor below 1 and becoming liquidatable without warning.",
    "paths": [
      "User in default eMode category borrows asset",
      "User calls setUserEMode to switch to category with lower collateral requirements",
      "User becomes undercollateralized without explicit warning"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "high",
    "title": "Oracle Price Manipulation Risk",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/GenericLogic.sol:127-130",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/ValidationLogic.sol:244-250"
    ],
    "claim": "The protocol uses spot prices from the oracle without any TWAP or price smoothing mechanism, allowing price manipulation in a single block.",
    "impact": "Attackers can manipulate asset prices to borrow more than allowed, trigger false liquidations, or steal funds through oracle manipulation.",
    "paths": [
      "Flash loan price manipulation in a single transaction",
      "Sandwich attacks around health factor calculations"
    ]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "high",
    "title": "feeToVault Can Be Set to Zero Address",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/pool/Pool.sol:624-626"
    ],
    "claim": "The setFeeToVault function allows setting the fee recipient to address(0), which would cause all feeToVaultPercent to be lost.",
    "impact": "Protocol fees intended for the vault are permanently lost if feeToVault is set to zero address, leading to economic loss for the protocol.",
    "paths": [
      "Admin calls setFeeToVault(address(0))"
    ]
  },
  {
    "id": "F-006",
    "severity": "High",
    "confidence": "medium",
    "title": "No Slippage Protection in Withdraw",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/SupplyLogic.sol:112-176"
    ],
    "claim": "The executeWithdraw function has no minimum amount parameter, exposing users to sandwich attacks and rounding losses.",
    "impact": "Users may receive less than expected due to market manipulation or rounding differences, with no recourse.",
    "paths": [
      "Front-run withdraw with large swap causing price impact",
      "Rounding errors in hToken burn calculations"
    ]
  },
  {
    "id": "F-007",
    "severity": "High",
    "confidence": "medium",
    "title": "Unbacked Minting Without Health Factor Check",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/BridgeLogic.sol:54-106"
    ],
    "claim": "The executeMintUnbacked function mints hTokens to a user without validating the recipient's health factor or collateral status.",
    "impact": "Bridge can mint unbacked tokens to any address, potentially creating accounting issues where users receive collateral they haven't actually supplied.",
    "paths": [
      "Bridge mints unbacked tokens to a user",
      "User immediately uses these as collateral to borrow"
    ]
  },
  {
    "id": "F-008",
    "severity": "High",
    "confidence": "medium",
    "title": "FlashLoan Premium Can Be Set to 100%",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/pool/Pool.sol:597-605",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol:466-478"
    ],
    "claim": "The flashloan premium total and liquidation protocol fee can each be set up to 100% (65535 = 655.35% actually), with no combined cap.",
    "impact": "Excessive flashloan fees can make the protocol unusable, or liquidations may fail if the total deduction exceeds 100%.",
    "paths": [
      "Set flashLoanPremiumTotal to a high value",
      "Set liquidationProtocolFee to a high value"
    ]
  },
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "high",
    "title": "Rebalance Stable Rate Does Not Validate New Rate",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/BorrowLogic.sol:295-316"
    ],
    "claim": "The executeRebalanceStableBorrowRate function burns the user's existing stable debt and mints new debt at the current rate without validating if the rate is reasonable or matches the old rate.",
    "impact": "Users' stable borrow rates can be changed arbitrarily by the pool admin or under certain conditions, potentially causing unexpected interest rate increases.",
    "paths": [
      "Trigger rebalanceStableBorrowRate on user's position"
    ]
  },
  {
    "id": "F-010",
    "severity": "Medium",
    "confidence": "medium",
    "title": "setLendingGauge Allows Zero Address Without Validation",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/pool/Pool.sol:572-577"
    ],
    "claim": "The setLendingGauge function allows setting the lending gauge to address(0), which will cause subsequent calls to updateAllocation() to fail silently or behave unexpectedly.",
    "impact": "Gauge allocation updates will fail for reserves with zero address lending gauge, potentially causing reward distribution issues.",
    "paths": [
      "Call setLendingGauge(asset, address(0))"
    ]
  },
  {
    "id": "F-011",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Missing Validation for Liquidation Bonus vs LTV Relationship",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol:93-115",
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol:122-144"
    ],
    "claim": "The liquidation threshold and liquidation bonus are not validated to ensure liquidation bonus > liquidation threshold, which could lead to inconsistent protocol behavior.",
    "impact": "Inconsistent liquidation parameters can cause unexpected liquidations or inability to liquidate positions.",
    "paths": [
      "Set liquidation threshold > liquidation bonus",
      "Liquidators may receive insufficient compensation"
    ]
  },
  {
    "id": "F-012",
    "severity": "Medium",
    "confidence": "low",
    "title": "Division by Zero in Health Factor Calculation",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/GenericLogic.sol:174-181"
    ],
    "claim": "If totalCollateralInBaseCurrency becomes zero during calculation but totalDebtInBaseCurrency is also zero, division by zero could occur in avgLtv/avgLiquidationThreshold calculations. However, the isEmpty check may prevent this.",
    "impact": "Potential revert in health factor calculation causing DoS for affected users.",
    "paths": [
      "User has debt but collateral value calculates to zero due to oracle failure"
    ]
  },
  {
    "id": "F-013",
    "severity": "Low",
    "confidence": "medium",
    "title": "No Access Control on initialize Function After First Initialization",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/pool/Pool.sol:102-108"
    ],
    "claim": "The initialize function uses the initializer modifier which only prevents multiple calls. If called with the correct provider, it can reset critical protocol parameters like flashLoanPremiumTotal and feeToVaultPercent.",
    "impact": "Although unlikely, the initializer can be re-entered if the proxy initialization wasn't completed, potentially resetting critical parameters.",
    "paths": [
      "Proxy initialization not completed",
      "Re-initialize with different parameters"
    ]
  },
  {
    "id": "F-014",
    "severity": "Low",
    "confidence": "medium",
    "title": "Integer Overflow in Isolation Mode Debt Calculation",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/logic/BorrowLogic.sol:137-147"
    ],
    "claim": "The isolation mode debt calculation uses toUint128() which can truncate values if the debt exceeds 2^128-1. However, the debt ceiling should prevent this.",
    "impact": "Potential truncation of isolation mode debt leading to incorrect accounting.",
    "paths": [
      "Borrow large amounts in isolation mode approaching uint128 max"
    ]
  },
  {
    "id": "F-015",
    "severity": "Low",
    "confidence": "medium",
    "title": "Missing Validation for Debt Ceiling in Isolation Mode",
    "locations": [
      "0x3a6d9bf8286a4ada77c15ecf82d4c0c0af95be74/lend-core/contracts/protocol/libraries/configuration/ReserveConfiguration.sol:439-459"
    ],
    "claim": "The debt ceiling can be set up to ~1 trillion (10^12) with 2 decimals, allowing significant exposure in isolation mode.",
    "impact": "Large debt ceilings in isolation mode can lead to significant protocol exposure if the isolated collateral is compromised.",
    "paths": [
      "Set very high debt ceiling for isolated asset",
      "Collateral asset price drops significantly"
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
