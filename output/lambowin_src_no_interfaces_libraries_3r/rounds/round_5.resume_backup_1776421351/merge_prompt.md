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
[
  {
    "id": "F-001",
    "severity": "High",
    "confidence": "high",
    "title": "VirtualToken.cashIn mints by msg.value for ERC20 underlyings, enabling unbacked minting/mis-accounting",
    "locations": [
      "VirtualToken.sol:72",
      "VirtualToken.sol:76",
      "VirtualToken.sol:78",
      "VirtualToken.sol:82",
      "VirtualToken.sol:138"
    ],
    "claim": "When `underlyingToken != NATIVE_TOKEN`, `cashIn(amount)` transfers `amount` underlying ERC20 but mints `msg.value` vTokens. This breaks 1:1 accounting: ERC20 deposits with `msg.value=0` mint zero, while nonzero ETH can mint vTokens without matching ERC20 backing.",
    "impact": "If any whitelisted address can invoke this path for an ERC20-backed VirtualToken, it can create unbacked redeemable supply and drain existing underlying liquidity, or cause insolvency/loss for honest depositors through under-minting.",
    "paths": [
      "Deploy/use VirtualToken with ERC20 underlying (`underlyingToken != NATIVE_TOKEN`).",
      "Whitelisted caller invokes `cashIn` with mismatched `amount` vs `msg.value` (e.g., `amount=0`, nonzero `msg.value`, or nonzero `amount`, `msg.value=0`).",
      "Contract mints by `msg.value` instead of deposited ERC20 amount.",
      "Caller later redeems via `cashOut` against real ERC20 balance."
    ],
    "round": 1,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-002",
    "severity": "Medium",
    "confidence": "high",
    "title": "Permissionless createLaunchPad can consume per-block vETH loan quota and DoS other launches",
    "locations": [
      "LamboFactory.sol:65",
      "LamboFactory.sol:70",
      "LamboFactory.sol:74",
      "VirtualToken.sol:93"
    ],
    "claim": "`createLaunchPad` is callable by anyone (only token address is whitelist-gated), and each call draws from global `MAX_LOAN_PER_BLOCK` via `takeLoan`. An attacker can consume the full quota first each block.",
    "impact": "Legitimate launch attempts in the same block can be forced to revert with `Loan limit per block exceeded`, enabling repeatable permissionless griefing/MEV denial of service.",
    "paths": [
      "Attacker calls `createLaunchPad(..., virtualLiquidityAmount = MAX_LOAN_PER_BLOCK, virtualLiquidityToken = whitelisted vToken)` early in block.",
      "VirtualToken records the full per-block loan allowance as used.",
      "Subsequent legitimate `createLaunchPad` calls in that block revert on the cap check.",
      "Attack repeats block-by-block with priority gas."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "Router sell pricing uses full vETH reserves including debt-locked liquidity, causing sell reverts and exit lockups",
    "locations": [
      "LamboFactory.sol:74",
      "VirtualToken.sol:97",
      "VirtualToken.sol:145",
      "LamboVEthRouter.sol:110",
      "LamboVEthRouter.sol:117",
      "LamboVEthRouter.sol:126"
    ],
    "claim": "Factory seeds pairs with debt-minted vETH (`takeLoan(pool, amount)`), and VirtualToken forbids transfers that move a debt address below its debt floor. Router sell quotes/swaps use raw pair reserves, which include debt-locked vETH that is not actually transferable out of the pair.",
    "impact": "Users can receive quotes based on unavailable reserveOut and hit reverts during swap transfer (`DebtOverflow`), creating practical sell failures and potential lockup of exit liquidity once non-debt vETH is depleted.",
    "paths": [
      "Pool receives vETH via `takeLoan(pool, virtualLiquidityAmount)` and `_debt[pool]` is increased.",
      "On sells, router computes `amountXOut` from full reserves (`getReserves` + `getAmountOut`).",
      "Pair attempts to transfer vETH output, but VirtualToken `_update` enforces `balance >= value + debt` for `from=pair`.",
      "If computed output exceeds transferable non-debt balance, transfer reverts and user sell fails."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-004",
    "severity": "Low",
    "confidence": "high",
    "title": "buyQuote refund logic withholds 1 wei from overpayments",
    "locations": [
      "LamboVEthRouter.sol:180",
      "LamboVEthRouter.sol:181"
    ],
    "claim": "Overpayment refunds are computed with an extra `-1` wei (`msg.value - amountXIn - fee - 1`) and only triggered when excess is greater than 1 wei.",
    "impact": "Users are systematically under-refunded by 1 wei when overpaying; residual ETH accumulates in the router as trapped dust.",
    "paths": [
      "User calls `buyQuote` with `msg.value` above required input+fee.",
      "Refund branch returns `excess - 1 wei` instead of full excess.",
      "1 wei remains in the contract per affected transaction."
    ],
    "round": 1,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "low",
    "title": "Rebalance initialization can be seized if deployment is non-atomic or proxy is left uninitialized",
    "locations": [
      "rebalance/LamboRebalanceOnUniwap.sol:40",
      "rebalance/LamboRebalanceOnUniwap.sol:53",
      "rebalance/LamboRebalanceOnUniwap.sol:55"
    ],
    "claim": "`initialize` is public and sets owner from a caller-supplied address. If deployment/upgrade flow ever leaves an instance (especially proxy) uninitialized, any external caller can initialize first and take ownership.",
    "impact": "Attacker ownership enables privileged control (upgrade authorization and `extractProfit`), allowing asset extraction or malicious upgrades.",
    "paths": [
      "Instance/proxy is deployed without immediate initializer execution.",
      "Attacker calls `initialize(attacker, vETH, pool, fee)` first.",
      "Attacker becomes owner and can authorize upgrades/extract managed tokens."
    ],
    "round": 1,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-006",
    "severity": "Critical",
    "confidence": "high",
    "title": "Launchpad creation reverts because factory transfers LP tokens to the zero address",
    "locations": [
      "LamboFactory.sol:79",
      "LamboFactory.sol:80"
    ],
    "claim": "`createLaunchPad` mints LP to the factory and then calls `IERC20(pool).safeTransfer(address(0), ...)`. For Uniswap V2-style LP ERC20 tokens (used by this code path via mainnet Uniswap V2 factory constants), transfers to `address(0)` revert, so launch creation cannot complete.",
    "impact": "Core launch flow is bricked: pool setup reverts and downstream flows that depend on successful launchpad creation (including router-assisted initial buy) fail.",
    "paths": [
      "Call `LamboFactory.createLaunchPad(...)` with a whitelisted virtual token.",
      "Function executes `IPool(pool).mint(address(this))` then attempts `IERC20(pool).safeTransfer(address(0), IERC20(pool).balanceOf(address(this)))`.",
      "LP token transfer to zero address reverts, reverting the full launch transaction."
    ],
    "round": 2,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-007",
    "severity": "High",
    "confidence": "high",
    "title": "Predictable clone address enables pair pre-creation that can indefinitely brick targeted launch attempts",
    "locations": [
      "LamboFactory.sol:57",
      "LamboFactory.sol:71",
      "LamboFactory.sol:72"
    ],
    "claim": "`createLaunchPad` deploys a non-deterministic clone (`Clones.clone`) and then calls `createPair`. The next clone address is predictable from the factory contract nonce, and Uniswap V2 `createPair` can be called permissionlessly for undeployed token addresses. An attacker can pre-create the pair for the next predicted clone address so `createPair` reverts.",
    "impact": "Launch creation for the targeted virtual liquidity token can be persistently DoS'd. Because the victim transaction reverts, the factory nonce rolls back, so retries keep targeting the same blocked clone address until some other successful create changes nonce.",
    "paths": [
      "Attacker predicts the next clone address for `LamboFactory`.",
      "Attacker calls Uniswap V2 factory `createPair(virtualLiquidityToken, predictedClone)` first.",
      "Victim calls `createLaunchPad`; clone deployment succeeds but `createPair` reverts due existing pair.",
      "Transaction reverts and factory nonce is unchanged, letting the attacker repeat the same block condition on retries."
    ],
    "round": 3,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-008",
    "severity": "Low",
    "confidence": "high",
    "title": "Rebalance ignores caller-provided output target and executes swaps with zero minimum return",
    "locations": [
      "rebalance/LamboRebalanceOnUniwap.sol:62",
      "rebalance/LamboRebalanceOnUniwap.sol:73",
      "rebalance/LamboRebalanceOnUniwap.sol:94",
      "rebalance/LamboRebalanceOnUniwap.sol:97",
      "rebalance/LamboRebalanceOnUniwap.sol:113"
    ],
    "claim": "`rebalance(directionMask, amountIn, amountOut)` accepts `amountOut` but never enforces it, and both buy/sell paths call `uniswapV3SwapTo(..., minReturn=0, ...)`.",
    "impact": "The strategy has no explicit slippage floor per execution, so adversarial order flow can capture most of the expected rebalance edge and leave only marginal profit to the protocol, degrading economic performance.",
    "paths": [
      "Operator/bot submits rebalance based on expected quote.",
      "MEV actors move price around the rebalance transaction.",
      "Swap still executes because `minReturn=0` and `amountOut` is unused.",
      "Transaction can settle at materially worse terms as long as final WETH delta stays positive."
    ],
    "round": 3,
    "source_agents": [
      "codex_1",
      "opencode_1"
    ]
  },
  {
    "id": "F-009",
    "severity": "Low",
    "confidence": "medium",
    "title": "Router and rebalance flows never enforce that configured vETH is native-backed, enabling full functional DoS via misconfiguration",
    "locations": [
      "LamboVEthRouter.sol:28",
      "LamboVEthRouter.sol:129",
      "LamboVEthRouter.sol:171",
      "rebalance/LamboRebalanceOnUniwap.sol:40",
      "rebalance/LamboRebalanceOnUniwap.sol:100",
      "rebalance/LamboRebalanceOnUniwap.sol:111"
    ],
    "claim": "Both router and rebalance hard-code ETH `cashIn/cashOut` assumptions against `vETH` but never validate `VirtualToken(vETH).underlyingToken()` is the native-token sentinel.",
    "impact": "If an ERC20-backed VirtualToken is configured as `vETH`, buy/sell/rebalance paths can revert or become incompatible, effectively bricking core trading/rebalance functionality.",
    "paths": [
      "Deploy/configure router or rebalance with a VirtualToken whose underlying is ERC20 instead of native ETH.",
      "Execution reaches `cashIn{value:...}` and/or ETH-dependent `cashOut` handling paths.",
      "Calls fail or downstream ETH transfer/wrapping logic breaks, reverting user operations."
    ],
    "round": 4,
    "source_agents": [
      "codex_1"
    ]
  },
  {
    "id": "F-010",
    "severity": "Low",
    "confidence": "medium",
    "title": "previewRebalance uses raw pool token balances, allowing donation-based signal manipulation",
    "locations": [
      "rebalance/LamboRebalanceOnUniwap.sol:128",
      "rebalance/LamboRebalanceOnUniwap.sol:129",
      "rebalance/LamboRebalanceOnUniwap.sol:130",
      "rebalance/LamboRebalanceOnUniwap.sol:135"
    ],
    "claim": "`previewRebalance` derives direction and size from `IERC20.balanceOf(uniswapPool)` values rather than robust pool-state pricing primitives, so direct token transfers to the pool can skew the preview signal.",
    "impact": "Automation that relies on `previewRebalance` can be induced into poor or reverting rebalance attempts, creating gas grief and degraded strategy execution quality.",
    "paths": [
      "Attacker transfers WETH or vETH directly to `uniswapPool`.",
      "`previewRebalance` computes manipulated `amountIn` and direction from distorted balances.",
      "Keeper/bot consuming preview output submits suboptimal rebalance parameters and loses execution quality (or reverts)."
    ],
    "round": 4,
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
    "id": "F-011",
    "severity": "High",
    "confidence": "low",
    "title": "Flash-loan callback is not bound to an active rebalance context",
    "locations": [
      "rebalance/LamboRebalanceOnUniwap.sol:62",
      "rebalance/LamboRebalanceOnUniwap.sol:71"
    ],
    "claim": "`onMorphoFlashLoan` only authenticates `msg.sender` and `amountIn == assets`; it does not enforce that the callback originated from this contract's own `rebalance` flow, so callback execution can occur without the outer `profit > 0` post-check.",
    "impact": "If an external path can trigger Morpho to call this callback directly, arbitrary zero-min-return swaps can be forced, potentially causing loss of contract-held inventory.",
    "paths": [
      "Attacker causes Morpho to invoke `onMorphoFlashLoan` with crafted `data`",
      "Contract executes `_executeBuy`/`_executeSell` using attacker-chosen parameters",
      "No callback-local profitability check prevents bad execution"
    ]
  },
  {
    "id": "F-012",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Unvalidated `directionMask` allows pool-word bit pollution in rebalance execution",
    "locations": [
      "rebalance/LamboRebalanceOnUniwap.sol:62",
      "rebalance/LamboRebalanceOnUniwap.sol:76",
      "rebalance/LamboRebalanceOnUniwap.sol:80",
      "rebalance/LamboRebalanceOnUniwap.sol:83"
    ],
    "claim": "User-controlled `directionMask` is OR'ed directly into the encoded pool word (`uint160(uniswapPool) | directionMask`) without sanitizing to `{0, _BUY_MASK}`, allowing low-bit contamination of the pool encoding.",
    "impact": "Rebalance can route through unintended pool encodings and execute with `minReturn = 0`, increasing the chance of malformed routing, failed execution, or adverse fills.",
    "paths": [
      "Caller passes crafted non-canonical `directionMask` to `rebalance`",
      "`onMorphoFlashLoan` builds polluted `pools[0]` value",
      "OKX router executes swap with corrupted pool encoding"
    ]
  },
  {
    "id": "F-013",
    "severity": "Medium",
    "confidence": "medium",
    "title": "Hardcoded integration addresses have no chain/environment validation",
    "locations": [
      "Utils/LaunchPadUtils.sol:16",
      "Utils/LaunchPadUtils.sol:21",
      "Utils/LaunchPadUtils.sol:24",
      "rebalance/LamboRebalanceOnUniwap.sol:30",
      "rebalance/LamboRebalanceOnUniwap.sol:31",
      "rebalance/LamboRebalanceOnUniwap.sol:33",
      "rebalance/LamboRebalanceOnUniwap.sol:34"
    ],
    "claim": "Core dependencies (WETH/factory/router/quoter/morpho/approve proxy) are hardcoded and never validated (no chain-id guard, no codehash/interface sanity checks).",
    "impact": "Deployments on the wrong network or against replaced addresses can result in permanent DoS, approvals to hostile spenders, or swap execution against malicious contracts.",
    "paths": [
      "Protocol is deployed where one or more hardcoded addresses do not match expected contracts",
      "Contracts still approve/call those addresses as trusted integrations",
      "Funds can be stuck, drained via approvals, or core flows become unusable"
    ]
  },
  {
    "id": "F-014",
    "severity": "Low",
    "confidence": "medium",
    "title": "Token implementation contract remains publicly initializable",
    "locations": [
      "LamboToken.sol:34",
      "LamboToken.sol:35",
      "LamboToken.sol:40"
    ],
    "claim": "`LamboToken.initialize` is unrestricted and one-time gated only by `_totalSupply == 0`, so the implementation contract itself can be initialized by any external caller.",
    "impact": "This can create a spoofed initialized implementation token with full supply minted to an attacker, increasing integration/UI confusion and phishing risk around canonical token addresses.",
    "paths": [
      "Attacker calls `initialize` on the implementation address before/without clone usage",
      "Implementation mints full supply to attacker-controlled address",
      "Off-chain/indexer/integration confusion may treat this token as legitimate"
    ]
  }
]

```

### Agent: opencode_1
```
[{"id":"F-011","severity":"Critical","confidence":"high","title":"takeLoan does not verify ETH payment - enables unbacked minting","locations":["VirtualToken.sol:88-100"],"claim":"The takeLoan function requires the payable modifier but does not verify that msg.value equals the amount borrowed. An attacker can call takeLoan with any amount and receive unbacked vETH tokens without depositing underlying ETH.","impact":"Attacker can steal virtual liquidity from the protocol by fabricating loans without providing ETH collateral, causing insolvency and draining the protocol's vETH reserves.","paths":["1. Attacker calls takeLoan(to, amount) with any amount","2. Function only verifies caller is valid factory and amount is within block limit","3. No msg.value check exists; attacker receives minted vETH for free","4. Attacker sells vETH for real ETH, causingProtocol insolvency"]},{"id":"F-012","severity":"High","confidence":"high","title":"cashIn for ERC20 underlying does not verify received amount matches minted amount","locations":["VirtualToken.sol:72-80"],"claim":"When underlyingToken is an ERC20 (not NATIVE_TOKEN), cashIn transfers assets from user via safeTransferFrom but mints tokens based on msg.value instead of the actual transferred amount.","impact":"Protocol creates unbacked virtual tokens when msg.value does not match the actual ERC20 amount transferred, or user can exploit mismatches to steal value.","paths":["1. User calls cashIn(amount) with msg.value = amount","2. Function transfers actual amount from user via _transferAssetFromUser","3. But mints tokens based on msg.value - if diff, mismatch between backed tokens and minted tokens","4. User can manipulate differences to extract value or cause accounting errors"]},{"id":"F-013","severity":"High","confidence":"high","title":"createLaunchPad lacks deadline - vulnerable to frontrunning and unexpected state","locations":["LamboFactory.sol:65-83"],"claim":"The createLaunchPad function has no deadline parameter, meaning the transaction can be executed at any time after submission. Attacker can monitor mempool and frontrun with higher gas to cause victim to get unfavorable pool state or revert.","impact":"Attackers can frontrun launchpad creation to steal favorable pool states, cause victim transactions to revert, or manipulate launch parameters at the victim's expense.","paths":["1. Victim submits createLaunchPad transaction","2. Attacker monitors mempool, sees transaction with favorable params","3. Attacker submits same params with higher gas","4. Victim's transaction either reverts or executes after unfavorably"]},{"id":"F-014","severity":"High","confidence":"medium","title":"LamboToken can be initialized by anyone before factory deployment","locations":["LamboToken.sol:34-42"],"claim":"The initialize function is public with no access control. If the implementation contract is not initialized, anyone can initialize it with custom name/symbol before factory clones it, potentially causing deployment failures or unexpected token configurations.","impact":"Implementation contract could be initialized with malicious parameters, causing all future clones to have unwanted names/symbols or breaking integration expectations.","paths":["1. Implementation contract is deployed but not initialized","2. Attacker calls initialize on the implementation","3. Later factory attempts to initialize clone fail or produce wrong token","4. Protocol functionality disrupted"]},{"id":"F-015","severity":"Medium","confidence":"high","title":"router does not validate actual ETH received in swap execution","locations":["LamboVEthRouter.sol:148-186"],"claim":"The _buyQuote function verifies msg.value >= amountXIn but does not check that the actual ETH received (after fees) matches what was expected for the swap. If ETH transfers fail silently, execution proceeds with incorrect amounts.","impact":"Silent ETH transfer failures can cause users to receive incorrect token amounts or lose funds due to insufficient input for the swap.","paths":["1. User calls buyQuote specifying amountXIn","2. Contract deducts fee, swaps remaining ETH","3. No verification that ETH actually entered the pair","4. User receives tokens but ETH may be less than expected"]},{"id":"F-016","severity":"Medium","confidence":"medium","title":"sellQuote transfers tokens to pair before verifying swap success","locations":["LamboVEthRouter.sol:102-146"],"claim":"In _sellQuote, tokens are transferred to the Uniswap pair before executing the swap. If the swap reverts for any reason, token transfers have already occurred causing potential loss of user funds.","impact":"If the swap execution fails after token transfer, users lose their tokens without receiving expected output, creating a recoverable loss scenario.","paths":["1. User calls sellQuote with amountYIn","2. Contract transfers quoteToken to pair","3. Swap executes - if it reverts, tokens already transferred","4. Call revert causes loss of tokens for user"]},{"id":"F-017","severity":"Medium","confidence":"medium","title":"rebalance allows permissionless flash loan profit extraction","locations":["LamboRebalanceOnUniwap.sol:62-69"],"claim":"The rebalance function can be called by anyone and uses flash loans to execute swaps. While profit is validated, anyone can trigger the rebalance and the contract will pay gas to execute trades that may not benefit the protocol.","impact":"Permissionless rebalance allows griefing via unnecessary gas expenditure, potential sandwich attacks on the swaps, and extraction of MEV that should belong to the protocol.","paths":["1. Anyone calls rebalance with chosen directionMask, amountIn, amountOut","2. Flash loan is taken and swaps execute","3. If profit > 0, caller receives profit (no extractProfit check)","4. Attackers can sandwich attack or waste protocol gas"]},{"id":"F-018","severity":"Medium","confidence":"medium","title":"extractProfit can drain any ERC20 token from contract","locations":["LamboRebalanceOnUniwap.sol:55-60"],"claim":"The extractProfit function allows the owner to extract any balance of any token. While this is intended for profit, it can accidentally drain tokens needed for rebalance operations (like WETH needed for flash loan repayment).","impact":"Owner may inadvertently drain operational tokens needed for contract function, causing rebalance transactions to fail and potentially leaving the contract unable to repay flash loans.","paths":["1. Owner calls extractProfit(to, token) for any token","2. If token is needed for operations (WETH for flash loan), balance becomes insufficient","3. Future rebalance calls will fail when attempting to repay flash loans","4. Contract stuck in unusable state"]},{"id":"F-019","severity":"Medium","confidence":"low","title":"initialize does not prevent multiple initialization","locations":["LamboRebalanceOnUniwap.sol:40-51"],"claim":"The initialize function uses the initializer modifier which should prevent re-initialization, but there is no upgradeability mechanism shown - if proxy is incorrectly configured, contract may be initializable multiple times or not at all.","impact":"If proxy setup is non-atomic, attacker could initialize with different parameters before rightful owner, seizing control of the rebalance contract.","paths":["1. Contract deployed as implementation","2. Proxy deployment non-atomic","3. Attacker initializes first with different owner","4. Legitimate initialization fails or changes wrong owner"]},{"id":"F-020","severity":"Low","confidence":"high","title":"getBuyQuote and getSellQuote are public view but allow free arbitrage detection","locations":["LamboVEthRouter.sol:59-83"],"claim":"These public view functions allow anyone to query the exact amounts they would receive for a given input without gas cost, enabling arbitrage bots to detect profitable opportunities and extract value before normal users can execute.","impact":"MEV extractors can use these free oracles to front-run profitable trades, degrading user experience and extracting value that would otherwise go to the protocol or users.","paths":["1. User initiates buy/sell transaction","2. MEV bot queries getBuyQuote/getSellQuote to get exact output","3. Bot front-runs with higher gas to capture arbitrage","4. User gets worse price or revert"]}]

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
