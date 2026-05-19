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
    "title": "VirtualToken cashIn mints by msg.value, enabling unbacked minting for ERC20 underlyings",
    "locations": [
      "VirtualToken.sol:72",
      "VirtualToken.sol:76",
      "VirtualToken.sol:78",
      "VirtualToken.sol:82",
      "VirtualToken.sol:138"
    ],
    "claim": "For non-native underlyings, cashIn transfers `amount` of ERC20 but mints `msg.value` vTokens. A whitelisted caller can mint without depositing underlying (e.g., `amount=0`, nonzero `msg.value`) and then redeem underlying via cashOut.",
    "impact": "If the contract holds underlying ERC20 liquidity, a whitelisted actor can drain it; even honest ERC20 deposits are mis-accounted and can lead to insolvency/loss.",
    "paths": [
      "Deploy VirtualToken with `underlyingToken != NATIVE_TOKEN`",
      "Whitelisted attacker calls `cashIn(0)` with nonzero `msg.value`",
      "Attacker receives vTokens equal to ETH sent, not ERC20 deposited",
      "Attacker calls `cashOut(...)` to withdraw real ERC20 backing"
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "medium",
    "title": "Upgradeable rebalance contract is takeover-prone if initialization is not atomic",
    "locations": [
      "rebalance/LamboRebalanceOnUniwap.sol:40",
      "rebalance/LamboRebalanceOnUniwap.sol:53",
      "rebalance/LamboRebalanceOnUniwap.sol:55"
    ],
    "claim": "`initialize` is public and sets ownership from a caller-supplied address. If a proxy is deployed without immediate initialization in the same transaction flow, any attacker can initialize first and become owner.",
    "impact": "Attacker ownership enables privileged actions, including upgrades (via UUPS auth path) and arbitrary token extraction through `extractProfit`.",
    "paths": [
      "Proxy is deployed pointing to this implementation but left uninitialized",
      "Attacker calls `initialize(attacker, vETH, pool, fee)` first",
      "Attacker uses owner privileges to upgrade and/or drain assets"
    ]
  },
  {
    "id": "F-003",
    "severity": "Medium",
    "confidence": "high",
    "title": "Permissionless createLaunchPad can exhaust MAX_LOAN_PER_BLOCK and deny launches",
    "locations": [
      "LamboFactory.sol:65",
      "LamboFactory.sol:70",
      "LamboFactory.sol:74",
      "VirtualToken.sol:93"
    ],
    "claim": "Anyone can call `createLaunchPad`, and each call consumes the global per-block loan quota in `VirtualToken.takeLoan`. An attacker can consume the full quota early each block.",
    "impact": "Legitimate launchpad creations can be repeatedly reverted (`Loan limit per block exceeded`) via low-cost griefing/MEV ordering.",
    "paths": [
      "Attacker submits `createLaunchPad(..., virtualLiquidityAmount=MAX_LOAN_PER_BLOCK, ...)` early in block",
      "Subsequent launch attempts in same block revert on loan-cap check",
      "Attack repeats each block with priority fees"
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "medium",
    "title": "Sell routing uses reserve math that includes debt-backed vETH that cannot be transferred out",
    "locations": [
      "LamboFactory.sol:74",
      "VirtualToken.sol:97",
      "VirtualToken.sol:145",
      "LamboVEthRouter.sol:110",
      "LamboVEthRouter.sol:117",
      "LamboVEthRouter.sol:126"
    ],
    "claim": "Launch pools receive debt-minted vETH, and router sell pricing uses full pair reserves. But `VirtualToken._update` blocks transfers that would reduce a debt address below its debt, so part of reserveOut is non-withdrawable.",
    "impact": "Sells can revert despite apparently sufficient reserves/quotes, creating exit failures and effective user lockup when real (non-debt) vETH liquidity is depleted.",
    "paths": [
      "Factory mints debt vETH into pair via `takeLoan(pool, amount)`",
      "Router computes sell output from total reserveOut",
      "If computed out exceeds transferable `(balance - debt)` portion, pair transfer fails in VirtualToken",
      "User sell reverts with no exit even though reserve-based quote looked valid"
    ]
  },
  {
    "id": "F-005",
    "severity": "Low",
    "confidence": "high",
    "title": "buyQuote refund logic systematically withholds 1 wei from overpaying users",
    "locations": [
      "LamboVEthRouter.sol:180",
      "LamboVEthRouter.sol:181"
    ],
    "claim": "Refund condition and amount subtract an extra `1` wei (`msg.value - amountXIn - fee - 1`), so overpayments are never fully refunded.",
    "impact": "Users are silently overcharged when sending excess ETH; dust accumulates in the router with no dedicated withdrawal path.",
    "paths": [
      "User calls `buyQuote` with `msg.value > quoted input`",
      "Router refunds `excess - 1 wei` instead of full excess",
      "1 wei remains trapped each affected trade"
    ]
  },
  {
    "id": "F-006",
    "severity": "High",
    "confidence": "low",
    "title": "Hardcoded external addresses create chain-deployment fund-loss risk",
    "locations": [
      "Utils/LaunchPadUtils.sol:16",
      "Utils/LaunchPadUtils.sol:21",
      "Utils/LaunchPadUtils.sol:24",
      "LamboFactory.sol:72",
      "LamboVEthRouter.sol:62"
    ],
    "claim": "Core integrations (WETH, Uniswap factory/router) are hardcoded constants with no chain-id validation or configurable constructor inputs.",
    "impact": "If deployed on a chain where these addresses are wrong or attacker-controlled, pool creation/swaps can route value to unintended contracts and cause direct fund loss.",
    "paths": [
      "Protocol deployed outside expected mainnet context",
      "A hardcoded address resolves to non-canonical/malicious contract",
      "Factory/router functions interact with attacker-controlled endpoint during launch/swap flows"
    ]
  },
  {
    "id": "F-007",
    "severity": "Medium",
    "confidence": "high",
    "title": "rebalance ignores `amountOut` and executes OKX swaps with `minReturn = 0`",
    "locations": [
      "rebalance/LamboRebalanceOnUniwap.sol:62",
      "rebalance/LamboRebalanceOnUniwap.sol:73",
      "rebalance/LamboRebalanceOnUniwap.sol:94",
      "rebalance/LamboRebalanceOnUniwap.sol:113"
    ],
    "claim": "User-supplied `amountOut` is decoded but never enforced, and both buy/sell swap calls pass `minReturn` as zero.",
    "impact": "There is no explicit execution-price guard at trade level; expected slippage bounds are absent, increasing manipulation/griefing surface and creating misleading operator assumptions.",
    "paths": [
      "Caller invokes `rebalance(directionMask, amountIn, highAmountOut)` expecting output bound",
      "Contract ignores `amountOut` and swaps with `minReturn=0`",
      "Trade executes at any price accepted by external router path"
    ]
  }
]

```

### Agent: opencode_1
```
[
    {
        "id": "F-001",
        "severity": "Critical",
        "confidence": "high",
        "title": "Front-Running Attack: initialize() Can Be Front-Run to Steal All Minted Tokens",
        "locations": [
            "LamboToken.sol:34-42"
        ],
        "claim": "The initialize() function in LamboToken can be called by anyone before the factory calls it, allowing an attacker to front-run the deployment and mint all tokens to themselves.",
        "impact": "An attacker can front-run the createLaunchPad transaction, call initialize() themselves to mint TOTAL_AMOUNT_OF_QUOTE_TOKEN (10^8 * 1e18) tokens to their address, then the factory's call will fail due to 'Already initialized'. The attacker steals all newly created tokens.",
        "paths": [
            "1. Attacker monitors mempool for createLaunchPad call",
            "2. Attacker calls initialize() with same name/tickname before factory transaction",
            "3. Attacker receives all minted tokens",
            "4. Factory transaction fails with 'Already initialized'"
        ]
    },
    {
        "id": "F-002",
        "severity": "Critical",
        "confidence": "high",
        "title": "Owner Can Drain All vETH From The Protocol Via updateFactory",
        "locations": [
            "VirtualToken.sol:57-60"
        ],
        "claim": "The updateFactory function allows the owner to add themselves as a valid factory, then call takeLoan to mint unlimited vETH tokens.",
        "impact": "A malicious owner can add their own address as a valid factory, call takeLoan() to mint unlimited vETH tokens, and drain all underlying assets from the protocol.",
        "paths": [
            "1. Owner calls updateFactory(attackerAddress, true)",
            "2. Owner calls takeLoan with arbitrary amount",
            "3. Owner mints unlimited vETH tokens"
        ]
    },
    {
        "id": "F-003",
        "severity": "Critical",
        "confidence": "high",
        "title": "Unlimited Token Minting via createLaunchPad with Zero Validation",
        "locations": [
            "LamboFactory.sol:65-83"
        ],
        "claim": "createLaunchPad has no access control beyond whitelist check. Any whitelisted virtualLiquidityToken can create unlimited quote tokens with arbitrary parameters.",
        "impact": "A malicious or compromised owner can create launchpads with any parameters, minting unlimited tokens that appear as legitimate protocol tokens.",
        "paths": [
            "1. Owner adds malicious virtualLiquidityToken to whitelist",
            "2. Owner calls createLaunchPad with fake tokens",
            "3. Unlimited fake tokens created"
        ]
    },
    {
        "id": "F-004",
        "severity": "Critical",
        "confidence": "high",
        "title": "No Slippage Protection Results in Potential Total Loss of Funds",
        "locations": [
            "LamboVEthRouter.sol:85-91",
            "LamboVEthRouter.sol:93-99"
        ],
        "claim": "The buyQuote and sellQuote functions accept minReturn parameter but there's no guarantee slippage protection is enforced by the caller, allowing MEV extraction or price manipulation to drain user funds.",
        "impact": "Users can set minReturn=0 and lose all funds during price manipulation or MEV extractors can sandwich trade to extract maximum value.",
        "paths": [
            "1. User calls buyQuote/sellQuote with minReturn=0",
            "2. Attacker front-runs with large trade to manipulate price",
            "3. User receives minimal output due to price impact"
        ]
    },
    {
        "id": "F-005",
        "severity": "High",
        "confidence": "medium",
        "title": "Fee Calculation Precision Loss Favors Protocol Over Users",
        "locations": [
            "LamboVEthRouter.sol:68-69",
            "LamboVEthRouter.sol:80-82"
        ],
        "claim": "Fee calculation (amountIn * feeRate) / feeDenominator truncates decimals, causing users to occasionally overpay fees.",
        "impact": "Small precision loss on each trade accumulates to protocol benefit. While individually small, this is a stealth tax on users.",
        "paths": []
    },
    {
        "id": "F-006",
        "severity": "High",
        "confidence": "high",
        "title": "No Slippage Protection in Rebalance Function",
        "locations": [
            "LamboRebalanceOnUniwap.sol:62-69"
        ],
        "claim": "The rebalance function executes flash loan and checks only profit > 0, with no minimum amountOut protection.",
        "impact": "If swap returns less than amountIn due to price impact or adverse market conditions, the transaction still executes and could result in losses being called 'profit' when they are actually losses.",
        "paths": [
            "1. Call rebalance with large amountIn",
            "2. Price moves unfavorably during execution",
            "3. Only checks profit > 0 without verifying amountOut is sufficient"
        ]
    },
    {
        "id": "F-007",
        "severity": "High",
        "confidence": "high",
        "title": "Missing Access Control on Rebalance Functions",
        "locations": [
            "LamboRebalanceOnUniwap.sol:55-59",
            "LamboRebalanceOnUniwap.sol:62-69"
        ],
        "claim": "extractProfit and rebalance functions are onlyOwner but the contract inherits from OwnableUpgradeable with _multiSign as owner, not a timelock or governance.",
        "impact": "The multiSign (owner) can extract all WETH/vETH from the contract at any time or rebalance to extract value from the vault.",
        "paths": [
            "1. Owner calls extractProfit to drain all tokens",
            "2. Owner calls rebalance with manipulated direction to extract value"
        ]
    },
    {
        "id": "F-008",
        "severity": "High",
        "confidence": "medium",
        "title": "Approval Reset Allows Potential Race Condition",
        "locations": [
            "LamboRebalanceOnUniwap.sol:86",
            "LamboRebalanceOnUniwap.sol:93",
            "LamboRebalanceOnUniwap.sol:112"
        ],
        "claim": "approve() is called without checking current allowance, blindly overwriting any existing approval. If approvals were already set for other purposes, they get overwritten.",
        "impact": "If called incorrectly or in combination with other contract functions that use OKXTokenApprove, could cause transaction failures.",
        "paths": []
    },
    {
        "id": "F-009",
        "severity": "Medium",
        "confidence": "high",
        "title": "Unverified underlyingToken Can Break VirtualToken",
        "locations": [
            "VirtualToken.sol:44-51"
        ],
        "claim": "underlyingToken is validated only to be non-zero, but could be an invalid ERC20 contract or address(1)-address(19) that doesn't behave as expected.",
        "impact": "If underlyingToken is invalid, cashIn/cashOut operations will fail persistently, locking all user funds.",
        "paths": [
            "1. Owner sets invalid underlyingToken",
            "2. All cashIn/cashOut operations fail",
            "3. User funds locked permanently"
        ]
    },
    {
        "id": "F-010",
        "severity": "Medium",
        "confidence": "medium",
        "title": "Reentrancy Protection on sellQuote Uses msg.sender.call Without Reentrancy Guard",
        "locations": [
            "LamboVEthRouter.sol:137-142"
        ],
        "claim": "The sellQuote function calls msg.sender.call{value: amountXOut} and then owner().call{value: fee} without checks-effects-interactions pattern.",
        "impact": "A malicious contract could implement a reentrant receive() to drain fees or manipulate the execution flow.",
        "paths": [
            "1. Attacker calls sellQuote with amountYIn",
            "2. In receive() callback, attacker calls sellQuote again",
            "3. State may be inconsistent during second call"
        ]
    }
]

```



## Excluded From Direct Audit Scope
Do not keep findings whose reportable root cause exists solely in files matching:
- `interfaces/**`
- `libraries/**`

Those files may still be read as context for in-scope implementation code.


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
