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
    "title": "Curve price skew or stETH depeg can permissionlessly DoS all strategy exits",
    "locations": [
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:160",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:181",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:208",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:313"
    ],
    "claim": "The strategy unwinds stETH through Curve using a near-par fixed minimum output (`slippageBps` defaults to 10 bps) instead of a live pool quote, and the vault swallows `divest` reverts. Any temporary price move beyond that threshold makes exit paths return zero.",
    "impact": "A permissionless attacker can front-run withdrawals, liquidations, rebalances, or strategy removals with a large stETH->ETH swap, force the Curve trade to revert, and leave vault capital stuck in the strategy. Organic stETH discounts have the same effect.",
    "paths": [
      "Attacker front-runs a vault withdrawal/liquidation with a large stETH->ETH trade on Curve",
      "Victim transaction reaches `_convertStEthToWeth` with `min_dy` still set near 1:1",
      "Curve exchange reverts, `AffineVault._divest` catches the revert and returns 0",
      "The vault cannot source the requested WETH from the strategy"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Balancer flash-loan fees are ignored, so any nonzero fee bricks the strategy",
    "locations": [
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/interfaces/balancer/IFlashLoanRecipient.sol:10",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:82",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:106"
    ],
    "claim": "`receiveFlashLoan` repays only the principal amount and completely ignores Balancer's `feeAmounts`, even though the interface requires principal plus fees to be returned before the callback finishes.",
    "impact": "If Balancer governance ever enables a nonzero flash-loan fee, every invest, divest, rebalance, and upgrade flow reverts. Because the strategy depends on flash loans to unwind Aave debt, funds can become effectively frozen.",
    "paths": [
      "Balancer flash-loan fee becomes nonzero",
      "Any call to `_flashLoan` enters `receiveFlashLoan`",
      "The callback transfers back only `ethBorrowed` instead of `ethBorrowed + feeAmounts[0]`",
      "Balancer reverts the entire operation, blocking deposits, withdrawals, and rebalances"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "medium",
    "title": "A slightly underwater Aave position makes `totalLockedValue()` revert and bricks vault recovery flows",
    "locations": [
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:234",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:191",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:302",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:372",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:492"
    ],
    "claim": "Strategy TVL is computed as `_collateral() - _debt()` with no floor. If debt ever equals or exceeds collateral, the subtraction underflows and reverts, and the vault directly calls this function in harvest, remove, withdraw, and rebalance flows.",
    "impact": "When the highly leveraged stETH/WETH Aave position is stressed, the vault loses the ability to harvest losses, remove the strategy, or liquidate it for withdrawals. The recovery path fails exactly when it is needed most.",
    "paths": [
      "Interest accrual, liquidation, or adverse price movement pushes debt to collateral or above",
      "`LidoLevV3.totalLockedValue()` underflows and reverts",
      "Vault calls that read strategy TVL revert during `harvest`, `removeStrategy`, `_withdrawFromStrategy`, or `rebalance`",
      "Operators cannot cleanly unwind or account for the distressed strategy"
    ]
  },
  {
    "id": "F-004",
    "severity": "Medium",
    "confidence": "medium",
    "title": "TVL and divest math assume 1 stETH = 1 ETH, overstating real withdrawable value",
    "locations": [
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:151",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:153",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:229",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:234"
    ],
    "claim": "The strategy values collateral with `getStETHByWstETH()` and subtracts WETH debt as if stETH always exits at par, but actual unwind routes through Curve at market price. `_getDivestFlashLoanAmounts()` then sizes flash-loan debt repayment from that inflated TVL.",
    "impact": "During any stETH discount, the vault overstates holdings and underestimates how much debt must be repaid to free a target amount of WETH. Withdrawals can come back short and accounting can drift toward insolvency.",
    "paths": [
      "stETH trades below ETH on Curve while the strategy still prices collateral at Lido's internal conversion rate",
      "Requested divest amount is mapped to too small a flash loan because TVL is overstated",
      "The unwind frees less WETH than the vault expects, leaving withdrawals or liquidations underfunded"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "low",
    "title": "Strategy reports more liquidated WETH than it actually transfers back to the vault",
    "locations": [
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:141",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:146",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:147",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:296",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:308",
      "0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:457"
    ],
    "claim": "`LidoLevV3._divest()` transfers only `min(unlockedWeth, amount)` back to the vault but returns `unlockedWeth`. The vault then treats that return value as `assetsReceived` and as liquidated liquidity.",
    "impact": "Vault accounting and events can claim that more WETH was liquidated than the vault actually received. Any upstream withdrawal or settlement logic that trusts `_withdrawFromStrategy()` or `_liquidate()` return values can over-release claims against too few assets.",
    "paths": [
      "A proportional unwind releases more WETH than the requested amount because of accrued profit or excess collateral",
      "The strategy sends only `amount` to the vault but returns the larger `unlockedWeth` value",
      "The vault propagates the inflated figure through `StrategyWithdrawal` and `_liquidate`"
    ]
  }
]

```

### Agent: opencode_1
```
Let me read the main contract files to identify vulnerabilities:
Based on my analysis of the smart contracts in the target directory, I've identified several security vulnerabilities. Let me provide the JSON array with all findings:

[
  {
    "id": "F-001",
    "severity": "Critical",
    "confidence": "high",
    "title": "Unchecked WSTETH wrapping return value allows loss of funds",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:123"],
    "claim": "In _addToPosition, the low-level call to wrap ETH into WSTETH uses (bool success,) = payable(address(WSTETH)).call{value: ethBorrowed}(\"\") without checking if the call actually succeeded or if the correct amount of WSTETH was received",
    "impact": "If the WSTETH.wrap() call fails or returns an unexpected amount, the function continues with an incorrect WSTETH balance. The subsequent AAVE deposit will use less collateral than expected, leading to smaller debt capacity and potential loss of funds",
    "paths": ["Attacker calls vault.depositIntoStrategy() with amount → strategy._afterInvest() → _addToPosition() → WSTETH.wrap() fails silently → deposit less collateral than expected → loss of funds"]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "medium",
    "title": "No slippage protection when wrapping ETH to WSTETH",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:123"],
    "claim": "The ETH to WSTETH wrapping in _addToPosition has no minimum amount parameter or slippage protection. The actual WSTETH received depends on the exchange rate which can vary",
    "impact": "If the WSTETH/ETH exchange rate becomes unfavorable (especially during market volatility), users receive less WSTETH than expected, resulting in losses that are not accounted for",
    "paths": ["Market volatility causes WSTETH/ETH rate to drop significantly → user invests → receives less WSTETH than expected → reduced collateral → user losses"]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Incorrect slippage calculation in _endPosition uses STETH balance instead of expected ETH",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:181"],
    "claim": "In _endPosition, the minAmount parameter for _convertStEthToWeth is calculated as STETH.balanceOf(address(this)).slippageDown(slippageBps) which applies slippage to the wrong value. It should apply slippage to the expected ETH output, not the input STETH amount",
    "impact": "The slippage protection is incorrectly applied and may allow trades with very low or zero minimum output, allowing MEV extractors or frontrunners to steal value from the strategy",
    "paths": ["Liquidator calls _endPosition → minAmount calculated incorrectly → Curve exchange accepts very low amount → value extracted by MEV"]
  },
  {
    "id": "F-004",
    "severity": "Critical",
    "confidence": "high",
    "title": "createAaveDebt can be called by any strategy without proper validation",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:334-340"],
    "claim": "The createAaveDebt function only checks if msg.sender is a valid strategy via _checkIfStrategy(Strategy(msg.sender)). This allows any active strategy in the vault to trigger debt creation on this contract, not just the legitimate upgrade path",
    "impact": "A malicious active strategy could call createAaveDebt on this contract to borrow WETH from AAVE and transfer it to themselves, effectively stealing the debt obligations of this strategy. This allows theft of protocol assets",
    "paths": ["Malicious strategy calls createAaveDebt on LidoLevV3 → borrows WETH from AAVE → transfers to attacker → this contract inherits the debt"]
  },
  {
    "id": "F-005",
    "severity": "High",
    "confidence": "high",
    "title": "Unbounded array in updateStrategyAllocations allows gas griefing",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:201-218"],
    "claim": "The updateStrategyAllocations function takes a Strategy[] calldata strategyList without any length limits. An attacker could pass an extremely large array causing the loop to iterate many times and consume all gas",
    "impact": "The function can be used to cause DoS by consuming all gas available, potentially blocking legitimate operations. While callstack depth might limit this, it still poses a griefing risk",
    "paths": ["Attacker calls updateStrategyAllocations with large array → loop exhausts gas → transaction reverts → disrupts vault operations"]
  },
  {
    "id": "F-006",
    "severity": "High",
    "confidence": "medium",
    "title": "setSlippageBps lacks proper access control and validation",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:265-267"],
    "claim": "The setSlippageBps function allows STRATEGIST_ROLE to set slippage without any upper bound check. A malicious strategist could set slippageBps to a very high value (e.g., 10000 = 100%) allowing sandwich attacks",
    "impact": "Malicious or compromised strategist can set excessive slippage tolerance enabling MEV bots to extract value from all strategy trades. Users funds are drained via unfavorable trades",
    "paths": ["Compromised strategist calls setSlippageBps(10000) → all future trades accept any slippage → MEV extractor profits → user losses"]
  },
  {
    "id": "F-007",
    "severity": "High",
    "confidence": "medium",
    "title": "setBorrowBps lacks bounds validation allowing excessive leverage",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:278-280"],
    "claim": "The setBorrowBps function allows STRATEGIST_ROLE to set borrowBps without upper bound validation. borrowBps can be set above MAX_BPS (10000) allowing borrowing more than 100% of collateral",
    "impact": "If borrowBps is set above the collateral value, the position becomes insolvent immediately. Additionally, if set above MAX_BPS, arithmetic in mulDivDown operations will produce incorrect results causing calculation errors and potential fund loss",
    "paths": ["Malicious strategist sets borrowBps > 10000 → position calculations wrong → liquidations fail → protocol loses funds"]
  },
  {
    "id": "F-008",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Rebalance can be called by any harvester without proper sequencing",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:476-521"],
    "claim": "The rebalance function is accessible to any address with HARVESTER role without requiring any pre-conditions or sequencing. Multiple rebalance calls in quick succession could lead to unexpected state",
    "impact": "While limited by role control, a malicious or compromised harvester could strategically time rebalance calls to cause suboptimal fund allocation or front-run other operations",
    "paths": ["Malicious harvester calls rebalance frequently → disrupts expected vault operations → causes user losses during withdrawals"]
  },
  {
    "id": "F-009",
    "severity": "Medium",
    "confidence": "low",
    "title": "No slippage protection in Curve exchange in _rebalancePosition",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:214"],
    "claim": "In _rebalancePosition for decLev, the _convertStEthToWeth call uses ethBorrowed as minAmount which may not provide adequate protection against slippage during the stETH to ETH swap",
    "impact": "During high volatility, the Curve exchange could return significantly less ETH than expected, and the minAmount check (being equal to the borrowed amount) doesn't protect against unfavorable swaps",
    "paths": ["High volatility period → rebalance called → Curve swap returns less ETH than expected → strategy loses value"]
  },
  {
    "id": "F-010",
    "severity": "Medium",
    "confidence": "high",
    "title": "Sweep function can extract any ERC20 from strategy including asset tokens",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/BaseStrategy.sol:69-71"],
    "claim": "The sweep function allows governance to transfer any ERC20 token from the strategy. There's no check to prevent sweeping the underlying asset token which is needed for strategy operations",
    "impact": "Governance could accidentally or intentionally sweep the asset tokens (e.g., USDC), leaving the strategy unable to fulfill withdrawal requests. While governance is trusted, this creates a single point of failure",
    "paths": ["Governance calls sweep on asset token → strategy loses ability to return funds → users cannot withdraw"]
  },
  {
    "id": "F-011",
    "severity": "Low",
    "confidence": "medium",
    "title": "Harvest can be called repeatedly to grief profit locking",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:348-401"],
    "claim": "The harvest function requires block.timestamp >= lastHarvest + LOCK_INTERVAL, but if called by multiple addresses with HARVESTER role in quick succession after the interval, there's no protection against front-running",
    "impact": "A harvester could monitor mempool and front-run another harvester's transaction to capture the fees, reducing the expected profit for the original harvester. This is a griefing vector rather than a direct fund loss",
    "paths": ["Two harvesters compete → front-running → MEV extraction → legitimate harvester loses expected fees"]
  },
  {
    "id": "F-012",
    "severity": "Critical",
    "confidence": "high",
    "title": "Missing reentrancy guard in receiveFlashLoan callback",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:82-107"],
    "claim": "The receiveFlashLoan function makes multiple external calls (to WETH.withdraw, AAVE operations, WSTETH.unwrap, Curve exchange) without a reentrancy guard. While Balancer is trusted, the callback interacts with multiple external protocols",
    "impact": "If any of the downstream contracts (AAVE, Curve, WSTETH) have reentrancy vulnerabilities or if the contract is upgraded to add malicious callbacks, reentrancy attacks could be possible. This is especially risky given the upgradeable nature suggestion from AccessStrategy inheritance",
    "paths": ["Contract upgraded with malicious callback → reenter receiveFlashLoan during external call → manipulate state → steal funds"]
  },
  {
    "id": "F-013",
    "severity": "High",
    "confidence": "medium",
    "title": "No slippage protection on AAVE deposit in _addToPosition",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:127"],
    "claim": "The AAVE.deposit call uses 0 for the minimum receive amount parameter. While AAVE deposits are generally 1:1 for aTokens, this doesn't account for potential aToken minting issues or rounding errors",
    "impact": "In extreme scenarios or future AAVE implementation changes, receiving fewer aTokens than expected could silently reduce collateral and increase effective leverage beyond intended levels",
    "paths": ["AAVE implementation change or edge case → fewer aTokens received → leverage higher than expected → liquidation risk"]
  },
  {
    "id": "F-014",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Strategy upgrade lacks deadline allowing stuck upgrades",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:306-318"],
    "claim": "The upgradeTo function has no time deadline. If the new strategy fails to complete its part of the upgrade (calling createAaveDebt), the old strategy will be stuck with unpaid flashloan",
    "impact": "If governance initiates an upgrade but the new strategy fails or refuses to complete the process, the old strategy is left with unpaid Balancer flashloan causing liquidation or stuck funds",
    "paths": ["Governance calls upgradeTo → new strategy fails to call createAaveDebt → old strategy cannot repay flashloan → liquidation"]
  },
  {
    "id": "F-015",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Fixed slippageBps value may be insufficient during market stress",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/strategies/LidoLevV3.sol:261"],
    "claim": "The default slippageBps is set to 10 (0.1%) which may be insufficient during periods of high market volatility or low liquidity. The comment says 'max slippage on curve is around 10bps for 10 eth' but this doesn't hold during stress",
    "impact": "During market stress, legitimate trades may revert due to slippage being exceeded, preventing users from withdrawing or rebalancing, potentially causing temporary lockup of funds",
    "paths": ["Market crash → liquidity drops → slippage exceeds 10bps → divest/rebalance fails → user funds locked"]
  },
  {
    "id": "F-016",
    "severity": "High",
    "confidence": "low",
    "title": "Potential integer overflow in _increaseTVLBps",
    "locations": ["0xcd6ca2f0d0c182c5049d9a1f65cde51a706ae142/src/vaults/AffineVault.sol:140-144"],
    "claim": "While there is a check newTotalBps <= MAX_BPS, if totalBps + tvlBps overflows (theoretically possible with maliciously crafted values thoughuint256 typically large enough), the check would pass incorrectly",
    "impact": "In practical Solidity 0.8.x, arithmetic overflows revert automatically, but if this code were ported to an older version or if the check were removed, overflow could allow invalid BPS allocations",
    "paths": ["Code ported to older Solidity → overflow undetected → BPS allocation broken → vault operations disrupted"]
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
