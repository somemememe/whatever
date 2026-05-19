# Audit Report

**Total findings:** 21

## Critical (1)

### F-006: Launchpad creation reverts because factory transfers LP tokens to the zero address

**Confidence:** high | **Locations:** `LamboFactory.sol:79, LamboFactory.sol:80`

createLaunchPad mints LP to the factory and then calls IERC20(pool).safeTransfer(address(0), ...). For Uniswap V2-style LP ERC20 tokens (used by this code path via mainnet Uniswap V2 factory constants), transfers to address(0) revert, so launch creation cannot complete.

**Impact:** Core launch flow is bricked: pool setup reverts and downstream flows that depend on successful launchpad creation (including router-assisted initial buy) fail.

**Paths:**

- Call LamboFactory.createLaunchPad(...) with a whitelisted virtual token.

- Function executes IPool(pool).mint(address(this)) then attempts IERC20(pool).safeTransfer(address(0), IERC20(pool).balanceOf(address(this))).

- LP token transfer to zero address reverts, reverting the full launch transaction.

*Round 2 | Agents: codex_1*

---

## High (3)

### F-001: VirtualToken.cashIn mints by msg.value for ERC20 underlyings, enabling unbacked minting/mis-accounting

**Confidence:** high | **Locations:** `VirtualToken.sol:72, VirtualToken.sol:76, VirtualToken.sol:78, VirtualToken.sol:82, VirtualToken.sol:138`

When underlyingToken != NATIVE_TOKEN, cashIn(amount) transfers amount underlying ERC20 but mints msg.value vTokens. This breaks 1:1 accounting: ERC20 deposits with msg.value=0 mint zero, while nonzero ETH can mint vTokens without matching ERC20 backing.

**Impact:** If any whitelisted address can invoke this path for an ERC20-backed VirtualToken, it can create unbacked redeemable supply and drain existing underlying liquidity, or cause insolvency/loss for honest depositors through under-minting.

**Paths:**

- Deploy/use VirtualToken with ERC20 underlying (underlyingToken != NATIVE_TOKEN).

- Whitelisted caller invokes cashIn with mismatched amount vs msg.value (e.g., amount=0, nonzero msg.value, or nonzero amount, msg.value=0).

- Contract mints by msg.value instead of deposited ERC20 amount.

- Caller later redeems via cashOut against real ERC20 balance.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-003: Router sell pricing uses full vETH reserves including debt-locked liquidity, causing sell reverts and exit lockups

**Confidence:** high | **Locations:** `LamboFactory.sol:74, VirtualToken.sol:97, VirtualToken.sol:145, LamboVEthRouter.sol:110, LamboVEthRouter.sol:117, LamboVEthRouter.sol:126`

Factory seeds pairs with debt-minted vETH (takeLoan(pool, amount)), and VirtualToken forbids transfers that move a debt address below its debt floor. Router sell quotes/swaps use raw pair reserves, which include debt-locked vETH that is not actually transferable out of the pair.

**Impact:** Users can receive quotes based on unavailable reserveOut and hit reverts during swap transfer (DebtOverflow), creating practical sell failures and potential lockup of exit liquidity once non-debt vETH is depleted.

**Paths:**

- Pool receives vETH via takeLoan(pool, virtualLiquidityAmount) and _debt[pool] is increased.

- On sells, router computes amountXOut from full reserves (getReserves + getAmountOut).

- Pair attempts to transfer vETH output, but VirtualToken _update enforces balance >= value + debt for from=pair.

- If computed output exceeds transferable non-debt balance, transfer reverts and user sell fails.

*Round 1 | Agents: codex_1*

---

### F-007: Predictable clone address enables pair pre-creation that can indefinitely brick targeted launch attempts

**Confidence:** high | **Locations:** `LamboFactory.sol:57, LamboFactory.sol:71, LamboFactory.sol:72`

createLaunchPad deploys a non-deterministic clone (Clones.clone) and then calls createPair. The next clone address is predictable from the factory contract nonce, and Uniswap V2 createPair can be called permissionlessly for undeployed token addresses. An attacker can pre-create the pair for the next predicted clone address so createPair reverts.

**Impact:** Launch creation for the targeted virtual liquidity token can be persistently DoS'd. Because the victim transaction reverts, the factory nonce rolls back, so retries keep targeting the same blocked clone address until some other successful create changes nonce.

**Paths:**

- Attacker predicts the next clone address for LamboFactory.

- Attacker calls Uniswap V2 factory createPair(virtualLiquidityToken, predictedClone) first.

- Victim calls createLaunchPad; clone deployment succeeds but createPair reverts due existing pair.

- Transaction reverts and factory nonce is unchanged, letting the attacker repeat the same block condition on retries.

*Round 3 | Agents: codex_1*

---

## Medium (7)

### F-002: Permissionless createLaunchPad can consume per-block vETH loan quota and DoS other launches

**Confidence:** high | **Locations:** `LamboFactory.sol:65, LamboFactory.sol:70, LamboFactory.sol:74, VirtualToken.sol:93`

createLaunchPad is callable by anyone (only token address is whitelist-gated), and each call draws from global MAX_LOAN_PER_BLOCK via takeLoan. An attacker can consume the full quota first each block.

**Impact:** Legitimate launch attempts in the same block can be forced to revert with Loan limit per block exceeded, enabling repeatable permissionless griefing/MEV denial of service.

**Paths:**

- Attacker calls createLaunchPad(..., virtualLiquidityAmount = MAX_LOAN_PER_BLOCK, virtualLiquidityToken = whitelisted vToken) early in block.

- VirtualToken records the full per-block loan allowance as used.

- Subsequent legitimate createLaunchPad calls in that block revert on the cap check.

- Attack repeats block-by-block with priority gas.

*Round 1 | Agents: codex_1*

---

### F-011: Router fees are bypassable through direct trading against the public launch pair

**Confidence:** high | **Locations:** `LamboFactory.sol:72, LamboFactory.sol:79, LamboVEthRouter.sol:132, LamboVEthRouter.sol:151, LamboVEthRouter.sol:171, VirtualToken.sol:143`

The buy/sell fee is charged only in LamboVEthRouter, while launch liquidity is placed in a normal public Uniswap V2 pair and vETH transfers are not restricted to the router except for per-address debt floors. Traders that can source or dispose of vETH externally can interact with the pair directly and avoid feeRate.

**Impact:** Protocol fee revenue is not enforceable at the contract layer. Once vETH is available through a vETH/WETH market, holders, or prior non-debt deposits into the pair, direct pair swaps can systematically bypass buy and sell fees.

**Paths:**

- Acquire vETH through the vETH/WETH market, another holder, or previous non-debt vETH liquidity.

- For a buy, transfer vETH directly to the launch Uniswap V2 pair and call swap for the quote token instead of LamboVEthRouter.buyQuote.

- For a sell, transfer quote tokens directly to the pair and call swap for vETH up to the pair's non-debt vETH balance, then route that vETH externally instead of using LamboVEthRouter.sellQuote.

- No router fee code executes on the direct pair path.

*Round 5 | Agents: codex_1*

---

### F-012: Rebalance swap direction and caller-supplied pool mask are not validated against pool token order

**Confidence:** medium | **Locations:** `rebalance/LamboRebalanceOnUniwap.sol:27, rebalance/LamboRebalanceOnUniwap.sol:62, rebalance/LamboRebalanceOnUniwap.sol:73, rebalance/LamboRebalanceOnUniwap.sol:76, rebalance/LamboRebalanceOnUniwap.sol:80, rebalance/LamboRebalanceOnUniwap.sol:83, rebalance/LamboRebalanceOnUniwap.sol:165`

The packed OKX/Uniswap V3 pool word is built by ORing a public caller-supplied directionMask into uniswapPool, and previewRebalance derives that mask from tokenIn == weth rather than checking whether tokenIn is the configured pool's token0. The contract only treats the exact _BUY_MASK value as a buy; every other bit pattern executes the sell branch while still being forwarded as descriptor bits.

**Impact:** For deployments where vETH sorts on the unexpected side of WETH, rebalance calls can request the wrong input token in the swap callback or produce output that the follow-up cashIn/cashOut logic does not handle, causing persistent rebalance failure. Arbitrary public masks can also trigger malformed or unintended swap descriptors, although concrete fund loss beyond failed execution depends on the external router's descriptor semantics.

**Paths:**

- Deploy/configure a vETH/WETH Uniswap V3 pool where token ordering does not match the contract's implicit WETH-side assumption.

- previewRebalance selects _BUY_MASK solely when tokenIn == weth and _SELL_MASK otherwise.

- rebalance passes that mask, or any caller-supplied mask, through to onMorphoFlashLoan, which ORs it into the pool word and chooses _executeBuy only for the exact _BUY_MASK value.

- The OKX/Uniswap V3 swap executes with the opposite direction or a malformed pool word, causing callback payment failure, wrong output handling, or full rebalance reverts.

*Round 5 | Agents: codex_1, opencode_1*

---

### F-013: Uniswap V2 fee switch can mint LP shares despite the intended burned-liquidity model

**Confidence:** medium | **Locations:** `LamboFactory.sol:72, LamboFactory.sol:79, LamboFactory.sol:80, Utils/LaunchPadUtils.sol:21`

Launch pools are created on the canonical Uniswap V2 factory, and the factory assumes moving the initially minted LP tokens away permanently removes all claims on reserves. If the Uniswap V2 feeTo switch is enabled, later mint/burn activity can mint protocol-fee LP tokens to feeTo even though the original LP was intended to be burned.

**Impact:** The external Uniswap feeTo address can receive a claim on launch-pool reserves and burn those LP shares to withdraw a portion of quote tokens and transferable vETH, violating the protocol's locked-liquidity assumption.

**Paths:**

- The canonical Uniswap V2 factory configured in LaunchPadUtils.UNISWAP_POOL_FACTORY_ has feeTo enabled.

- A launch pool accumulates swap-fee growth after initial liquidity is minted and moved away.

- A later liquidity mint or burn triggers Uniswap V2 protocol-fee minting to feeTo.

- feeTo burns the minted LP shares and withdraws its proportional share of pool reserves.

*Round 5 | Agents: codex_1*

---

### F-017: Valid factories can repay and burn debt for arbitrary borrowers, allowing cross-factory launch-pair reserve corruption

**Confidence:** medium | **Locations:** `VirtualToken.sol:39, VirtualToken.sol:57, VirtualToken.sol:105, VirtualToken.sol:106, VirtualToken.sol:107`

repayLoan lets any address marked in validFactories decrease _debt[to] and burn amount of vTokens from arbitrary to without tracking which factory originated the debt, requiring borrower consent, or verifying an associated repayment flow.

**Impact:** A compromised, buggy, or overly broad valid factory can burn vETH directly out of existing launch pairs, leaving AMM reserves stale versus token balances. Subsequent swaps can revert until the deficit is refilled, or a sync can permanently crystallize the reserve loss and impair exit liquidity.

**Paths:**

- A VirtualToken owner has authorized more than one factory, or an authorized factory becomes buggy/compromised.

- That valid factory calls repayLoan(launchPair, debtAmount) for a pair whose debt was created by another factory or launch flow.

- VirtualToken decreases the pair's debt and burns the pair's vETH balance without any AMM reserve update or borrower approval.

- The pair's recorded reserves exceed its actual vETH balance, causing later swaps to revert or forcing a sync that realizes the missing reserve.

*Round 7 | Agents: codex_1*

---

### F-018: Valid factories can mint debt into existing pairs as phantom swap input

**Confidence:** medium | **Locations:** `VirtualToken.sol:57, VirtualToken.sol:88, VirtualToken.sol:96, VirtualToken.sol:97`

takeLoan lets any address marked in validFactories mint vETH debt to an arbitrary address without proving that the borrower is a fresh pair controlled by that factory or that the pair is immediately synchronized.

**Impact:** A compromised, buggy, or overly broad valid factory can mint debt into an existing vETH pair, increasing the pair's token balance while reserves remain stale. A subsequent swap can treat the unsynced minted vETH as input and withdraw the paired quote token, corrupting or draining launch-pair reserves while the added vETH remains debt-locked.

**Paths:**

- A VirtualToken owner has authorized more than one factory, or an authorized factory becomes buggy/compromised.

- That valid address calls takeLoan(existingLaunchPair, amount) instead of minting only to a newly created launch pair.

- The existing pair's vETH balance increases but its reserves are not updated.

- An attacker calls swap on the existing pair to withdraw quoteToken; the pair accounts the unsynced vETH balance delta as amountIn.

- The pair is left with debt-locked vETH and reduced quote reserves.

*Round 8 | Agents: codex_1*

---

### F-020: Debt-locked vETH can make externally minted launch-pair LP shares non-burnable

**Confidence:** high | **Locations:** `LamboFactory.sol:72, LamboFactory.sol:74, LamboFactory.sol:79, VirtualToken.sol:143, VirtualToken.sol:145, VirtualToken.sol:146`

Launch pairs receive initial vETH as debt via takeLoan, and VirtualToken prevents the pair from transferring any vETH amount that would leave its balance below that debt. Uniswap V2 LP accounting is unaware of this debt floor, so later public LP providers can receive shares whose pro-rata vETH withdrawal claim exceeds the pair's debt-free transferable vETH balance.

**Impact:** Users or integrations that add liquidity directly to the public launch pair can have full LP burns revert and, once debt-free vETH is sufficiently depleted, can be unable to withdraw their contributed quote tokens and vETH until enough later buys restore transferable vETH. This turns normal trading against the launch pair into a lockup risk for externally minted LP shares.

**Paths:**

- Factory creates a public Uniswap V2 launch pair and mints virtualLiquidityAmount vETH debt to the pair with takeLoan.

- A third party sources transferable vETH, transfers proportional vETH and quoteToken to the pair, and calls the pair's public mint, receiving LP shares.

- Subsequent quote-token sells remove debt-free vETH from the pair while the original debt remains fixed.

- The LP holder calls burn; the pair computes a pro-rata vETH amount from total vETH balance including debt-locked vETH, then attempts to transfer that amount.

- VirtualToken._update reverts with DebtOverflow when the transfer would make balanceOf(pair) fall below _debt[pair], reverting the burn and blocking withdrawal.

*Round 9 | Agents: codex_1*

---

## Low (10)

### F-004: buyQuote refund logic withholds 1 wei from overpayments

**Confidence:** high | **Locations:** `LamboVEthRouter.sol:180, LamboVEthRouter.sol:181`

Overpayment refunds are computed with an extra -1 wei (msg.value - amountXIn - fee - 1) and only triggered when excess is greater than 1 wei.

**Impact:** Users are systematically under-refunded by 1 wei when overpaying; residual ETH accumulates in the router as trapped dust.

**Paths:**

- User calls buyQuote with msg.value above required input+fee.

- Refund branch returns excess - 1 wei instead of full excess.

- 1 wei remains in the contract per affected transaction.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-005: Rebalance initialization can be seized if deployment is non-atomic or proxy is left uninitialized

**Confidence:** low | **Locations:** `rebalance/LamboRebalanceOnUniwap.sol:40, rebalance/LamboRebalanceOnUniwap.sol:53, rebalance/LamboRebalanceOnUniwap.sol:55`

initialize is public and sets owner from a caller-supplied address. If deployment/upgrade flow ever leaves an instance (especially proxy) uninitialized, any external caller can initialize first and take ownership.

**Impact:** Attacker ownership enables privileged control (upgrade authorization and extractProfit), allowing asset extraction or malicious upgrades.

**Paths:**

- Instance/proxy is deployed without immediate initializer execution.

- Attacker calls initialize(attacker, vETH, pool, fee) first.

- Attacker becomes owner and can authorize upgrades/extract managed tokens.

*Round 1 | Agents: codex_1*

---

### F-008: Rebalance ignores caller-provided output target and executes swaps with zero minimum return

**Confidence:** high | **Locations:** `rebalance/LamboRebalanceOnUniwap.sol:62, rebalance/LamboRebalanceOnUniwap.sol:73, rebalance/LamboRebalanceOnUniwap.sol:94, rebalance/LamboRebalanceOnUniwap.sol:97, rebalance/LamboRebalanceOnUniwap.sol:113`

rebalance(directionMask, amountIn, amountOut) accepts amountOut but never enforces it, and both buy/sell paths call uniswapV3SwapTo(..., minReturn=0, ...).

**Impact:** The strategy has no explicit slippage floor per execution, so adversarial order flow can capture most of the expected rebalance edge and leave only marginal profit to the protocol, degrading economic performance.

**Paths:**

- Operator/bot submits rebalance based on expected quote.

- MEV actors move price around the rebalance transaction.

- Swap still executes because minReturn=0 and amountOut is unused.

- Transaction can settle at materially worse terms as long as final WETH delta stays positive.

*Round 3 | Agents: codex_1, opencode_1*

---

### F-009: Router and rebalance flows never enforce that configured vETH is native-backed, enabling full functional DoS via misconfiguration

**Confidence:** medium | **Locations:** `LamboVEthRouter.sol:28, LamboVEthRouter.sol:129, LamboVEthRouter.sol:171, rebalance/LamboRebalanceOnUniwap.sol:40, rebalance/LamboRebalanceOnUniwap.sol:100, rebalance/LamboRebalanceOnUniwap.sol:111`

Both router and rebalance hard-code ETH cashIn/cashOut assumptions against vETH but never validate VirtualToken(vETH).underlyingToken() is the native-token sentinel.

**Impact:** If an ERC20-backed VirtualToken is configured as vETH, buy/sell/rebalance paths can revert or become incompatible, effectively bricking core trading/rebalance functionality.

**Paths:**

- Deploy/configure router or rebalance with a VirtualToken whose underlying is ERC20 instead of native ETH.

- Execution reaches cashIn{value:...} and/or ETH-dependent cashOut handling paths.

- Calls fail or downstream ETH transfer/wrapping logic breaks, reverting user operations.

*Round 4 | Agents: codex_1*

---

### F-010: previewRebalance uses raw pool token balances, allowing donation-based signal manipulation

**Confidence:** medium | **Locations:** `rebalance/LamboRebalanceOnUniwap.sol:128, rebalance/LamboRebalanceOnUniwap.sol:129, rebalance/LamboRebalanceOnUniwap.sol:130, rebalance/LamboRebalanceOnUniwap.sol:135`

previewRebalance derives direction and size from IERC20.balanceOf(uniswapPool) values rather than robust pool-state pricing primitives, so direct token transfers to the pool can skew the preview signal.

**Impact:** Automation that relies on previewRebalance can be induced into poor or reverting rebalance attempts, creating gas grief and degraded strategy execution quality.

**Paths:**

- Attacker transfers WETH or vETH directly to uniswapPool.

- previewRebalance computes manipulated amountIn and direction from distorted balances.

- Keeper/bot consuming preview output submits suboptimal rebalance parameters and loses execution quality (or reverts).

*Round 4 | Agents: codex_1*

---

### F-014: Whitelisted router can be used as a generic arbitrary-pair vETH redemption adapter

**Confidence:** medium | **Locations:** `LamboVEthRouter.sol:93, LamboVEthRouter.sol:107, LamboVEthRouter.sol:109, LamboVEthRouter.sol:126, LamboVEthRouter.sol:129, VirtualToken.sol:82`

VirtualToken.cashOut is whitelist-gated, but the whitelisted router's sellQuote accepts any quoteToken, derives the canonical Uniswap V2 pair only from quoteToken/vETH, and never checks that the quote token or pair came from LamboFactory. A caller can therefore make the router receive vETH from an arbitrary pair and have the router redeem it.

**Impact:** The cashOut whitelist is not an effective boundary for vETH redemption. Any non-whitelisted account that can source transferable vETH can redeem it through an attacker-created pair; if transferable unbacked or mis-accounted vETH reaches users through another integration or bug, the router path can convert it into underlying ETH.

**Paths:**

- Attacker obtains transferable vETH.

- Attacker creates and seeds a Uniswap V2 pair between vETH and an attacker-controlled quote token.

- Attacker calls sellQuote(attackerToken, amountYIn, minReturn).

- The router swaps the attacker token for vETH from the arbitrary pair, calls VirtualToken(vETH).cashOut(amountXOut), and forwards ETH to the caller minus the router fee.

*Round 6 | Agents: codex_1*

---

### F-015: Native ETH accepted by router and rebalancer has no recovery path

**Confidence:** high | **Locations:** `LamboVEthRouter.sol:188, rebalance/LamboRebalanceOnUniwap.sol:55, rebalance/LamboRebalanceOnUniwap.sol:168`

Both LamboVEthRouter and LamboRebalanceOnUniwap accept native ETH through receive() functions, but neither exposes a native-ETH withdrawal or rescue function. The rebalancer's extractProfit only transfers ERC20 balances via IERC20(token).balanceOf and safeTransfer.

**Impact:** Accidental direct ETH transfers, forced ETH, and unexpected native ETH residuals can become permanently stuck. In the router this also compounds the trapped-dust behavior from refund underpayment, and in the rebalancer pre-existing native ETH is excluded from the _executeBuy wrapping delta.

**Paths:**

- Send ETH directly to LamboVEthRouter.receive() or leave refund dust in the router.

- Send or force ETH to LamboRebalanceOnUniwap.receive().

- Attempt recovery through available functions; the router has no withdrawal method and the rebalancer can only sweep ERC20 balances through extractProfit.

*Round 6 | Agents: codex_1*

---

### F-016: Rebalance preview can be unusable against non-view V3 quoters

**Confidence:** medium | **Locations:** `rebalance/LamboRebalanceOnUniwap.sol:116, rebalance/LamboRebalanceOnUniwap.sol:155`

previewRebalance is declared view and calls the hard-coded quoter through a view-typed call path, causing Solidity to issue STATICCALL for the quote. QuoterV2-style contracts compute quotes by invoking pool swap logic and reverting with quote data, which is incompatible with static execution once pool state-write logic is reached.

**Impact:** The intended preview path can revert instead of returning amountIn, amountOut, and directionMask, disabling simple keeper discovery and allowing vETH/WETH imbalance to persist unless callers implement their own off-chain quoting.

**Paths:**

- A keeper calls previewRebalance().

- The function reaches quoteExactInputSingleWithPool through a static call because previewRebalance and the called interface are view.

- A QuoterV2-style implementation attempts non-view pool swap simulation and reverts under STATICCALL.

- No rebalance parameters are returned for automation.

*Round 7 | Agents: codex_1*

---

### F-019: Permissionless rebalance accepts arbitrary trade sizes unrelated to the preview target

**Confidence:** low | **Locations:** `rebalance/LamboRebalanceOnUniwap.sol:62, rebalance/LamboRebalanceOnUniwap.sol:64, rebalance/LamboRebalanceOnUniwap.sol:67, rebalance/LamboRebalanceOnUniwap.sol:68, rebalance/LamboRebalanceOnUniwap.sol:116`

rebalance accepts caller-supplied amountIn and never derives or bounds it from previewRebalance; the only postcondition is that the contract's WETH balance increases by more than zero.

**Impact:** A permissionless caller can use the whitelisted rebalancer's flash-loan and vETH cashIn/cashOut authority to execute any still-profitable trade size, not just the previewed correction. This can over-move the configured vETH/WETH pool while leaving only marginal WETH profit to the protocol, degrading pool pricing and execution quality for users or LPs.

**Paths:**

- Caller observes or computes a profitable rebalance direction.

- Caller supplies an amountIn materially larger than the previewRebalance amount.

- The swap remains net-positive for the rebalancer, or only marginally positive after external positioning.

- The transaction passes the profit > 0 check even though the pool has been pushed beyond the intended rebalance size.

*Round 8 | Agents: codex_1*

---

### F-021: Initial-buy helper has no caller slippage floor against mutable router fees

**Confidence:** medium | **Locations:** `LamboVEthRouter.sol:35, LamboVEthRouter.sol:36, LamboVEthRouter.sol:56, LamboVEthRouter.sol:151, LamboVEthRouter.sol:152, LamboVEthRouter.sol:153, LamboVEthRouter.sol:167, LamboVEthRouter.sol:168`

createLaunchPadAndInitialBuy always calls _buyQuote with minReturn set to 0, while the router owner can update feeRate up to feeDenominator. _buyQuote transfers the fee to owner before swapping only the post-fee ETH, and the initial-buy caller has no parameter to require a minimum amount of quote tokens.

**Impact:** A malicious or compromised fee owner can set or front-run a near-100% fee so an initial buyer's buyAmount is mostly paid as fee and the user receives only dust without a slippage revert. At feeRate equal to feeDenominator, the post-fee input becomes zero and nonzero buys revert, creating an owner-controlled buy DoS.

**Paths:**

- Router owner sets feeRate close to feeDenominator before a user calls createLaunchPadAndInitialBuy with buyAmount > 0.

- createLaunchPadAndInitialBuy creates the launch pool and then calls _buyQuote(quoteToken, buyAmount, 0).

- _buyQuote sends most of buyAmount to owner as fee, computes output on the small post-fee remainder, and accepts any positive or zero quote-token output because minReturn is zero.

- The initial buyer cannot make the combined launch-and-buy transaction revert based on a minimum expected quote-token amount.

*Round 10 | Agents: codex_1*

---
