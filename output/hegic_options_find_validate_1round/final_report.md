# Audit Report

**Total findings:** 17

## Critical (2)

### F-001: Utilization is enforced on partial collateral, allowing option liabilities to exceed pool assets

**Confidence:** high | **Locations:** `0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:190, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:195, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:208, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:307, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicCall.sol:60, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPut.sol:74, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPut.sol:80`

The pool caps new sales using `lockedAmount`, but `lockedAmount` is only `collateralizationRatio%` of the option notional while exercise PnL can be much larger and can approach the full notional for calls or the full cash-settled payoff for puts. As a result, the protocol can sell more option exposure than its assets can honor after a large move.

**Impact:** A user can permissionlessly drive the pool insolvent by filling utilization up to the configured limit and later exercising after a sharp price move. Once aggregate profits exceed pool assets, profitable option holders compete for insufficient liquidity and later exercises revert or go unpaid.

**Paths:**

- Buy ATM options until `(lockedAmount + amountToBeLocked) * 100 <= totalBalance * maxUtilizationRate` is saturated.

- Because only a fraction of notional is locked, aggregate exercise profit can materially exceed aggregate `lockedAmount` after a large underlying move.

- Early exercisers drain the pool and later ITM option exercises fail when `totalBalance` is insufficient.

*Round 1 | Agents: codex*

---

### F-008: Closed liquidity tranches can be withdrawn repeatedly because tranche state is never enforced

**Confidence:** high | **Locations:** `0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:394, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:403, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:410, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:416, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:444`

`_withdraw()` marks a tranche as `Closed`, but the only `require(t.state == TrancheState.Open)` check is commented out and the tranche NFT is never burned. Because ownership remains intact, the same tranche holder can call `withdraw()` again and receive the tranche's share of the now-smaller pool repeatedly.

**Impact:** A liquidity provider can drain other LPs' capital, and potentially active option backing, by withdrawing the same tranche multiple times. This is a direct theft vector that can empty the pool until later withdrawals or exercises revert.

**Paths:**

- Deposit liquidity and wait until the lockup period has passed.

- Call `withdraw(trancheID)` once; the tranche is marked closed but still exists and remains owned by the attacker.

- Call `withdraw(trancheID)` again before other LPs exit; the contract reuses the same `t.share` against the remaining `totalBalance` and transfers more funds to the attacker.

*Round 1 | Agents: merge-review*

---

## High (5)

### F-004: Chainlink oracle reads are used without freshness or round-validity checks

**Confidence:** medium | **Locations:** `0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:508, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Options/SimplePriceCalculator.sol:123, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Options/PriceCalculatorWtihUtilizationRate.sol:152`

The protocol reads `latestRoundData().answer` and uses it directly for strike setting, premium calculation, collateral sizing, and exercise settlement, but it never checks `updatedAt`, `answeredInRound`, or any staleness/completeness condition. This means stale or incomplete oracle rounds are trusted throughout the option lifecycle.

**Impact:** During oracle outages or delayed updates, users can buy or exercise options against stale prices, causing material mispricing and incorrect payouts. Because the same unchecked feed is reused across pricing and settlement, a bad round can affect both opening and closing flows.

**Paths:**

- The Chainlink feed stops updating or returns an incomplete round while still exposing the last answer.

- Users open or exercise options while the contracts continue to trust that answer as current.

- Premiums, locked collateral, strikes, or settlement profits are computed from stale data, harming LPs or traders depending on the direction of the mismatch.

*Round 1 | Agents: codex*

---

### F-005: Anyone can approve attacker-controlled pools to spend arbitrary Facade token balances

**Confidence:** high | **Locations:** `0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:126, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:127, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:128`

`Facade.poolApprove()` is publicly callable and trusts any `IHegicPool` implementation. A malicious contract can return an arbitrary ERC20 from `token()`, causing the Facade to grant that malicious contract unlimited allowance over that token with no access control or pool whitelist.

**Impact:** Any ERC20 balances held by the Facade, including accidentally sent funds or balances stranded for any other reason, become permissionlessly stealable. An attacker only needs to deploy a fake pool and then drain the approved token with `transferFrom`.

**Paths:**

- Deploy a malicious contract implementing `IHegicPool` whose `token()` returns the target ERC20.

- Call `Facade.poolApprove(maliciousPool)` to obtain unlimited allowance from the Facade.

- Invoke the malicious pool's transfer logic or a direct `transferFrom` path to move the Facade's token balance to the attacker.

*Round 1 | Agents: codex*

---

### F-009: LP withdrawals are not limited to unlocked liquidity, so active option collateral can be removed before expiry

**Confidence:** high | **Locations:** `0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:404, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:416, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:418, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:421, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:427`

Withdrawals are paid from pro-rata `totalBalance` with no check against `availableBalance() = totalBalance - lockedAmount`. Since option periods can last up to 90 days while LP lockup is only 30 days by default, LPs can withdraw funds that are still supposed to collateralize active options.

**Impact:** Liquidity providers can exit with reserved collateral while options are still live, leaving the pool unable to honor later exercises. This creates a permissionless path to undercollateralize outstanding options and can cause exercise failures or insolvency even without a large market move.

**Paths:**

- An LP deposits, the pool sells options, and `lockedAmount` increases.

- After the LP lockup expires but before the options expire, the LP calls `withdraw()` and receives a pro-rata share of full `totalBalance`, including locked collateral.

- When an option later becomes profitable, exercise reverts or fails economically because the reserved backing has already been withdrawn.

*Round 1 | Agents: merge-review*

---

### F-012: Facade accepts arbitrary payment paths and can spend its own pool-token balance to subsidize options

**Confidence:** high | **Locations:** `onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:85, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:155, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:157, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:166, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:174, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:220`

`Facade.createOption` never verifies that `swappath` ends in `pool.token()` or even that any swap happens. If `swappath.length == 1`, the Facade simply pulls `swappath[0]` from the buyer and then calls `pool.sellOption`, which charges the Facade in the real pool token. If the Facade already holds some pool-token balance, the buyer can pay with an arbitrary token while the Facade subsidizes the actual premium from its own balance.

**Impact:** Any pool-token balance that accumulates inside the Facade, including leftovers stranded by exact-output swaps or accidental transfers, can be drained by attackers to mint subsidized or effectively free options. This converts trapped balances into a permissionless subsidy for arbitrary option buyers until the Facade's real pool-token inventory is exhausted.

**Paths:**

- The Facade accumulates some balance of `pool.token()` from prior overpayments, dust, or accidental transfers.

- An attacker calls `createOption` with a one-hop `swappath` pointing to an arbitrary ERC20, or a multi-hop path whose output token is not `pool.token()`.

- The Facade pulls the attacker-chosen token, performs no relevant conversion into the pool token, and then `pool.sellOption` pulls the real premium from the Facade's existing `pool.token()` balance.

*Round 1 | Agents: codex, merge-review*

---

### F-101: ETH deposit helper trusts arbitrary pools and can spend the Facade’s internal token balances

**Confidence:** high | **Locations:** `onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:126, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:127, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:128, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:182, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:187, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:188, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:190, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:324, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:350`

`provideEthToPool` blindly wraps ETH into WETH and then calls an arbitrary `pool.provideFrom(msg.sender, msg.value, hedged, minShare)` without verifying that the pool is trusted or that `pool.token()` is WETH. The helper also grants the target pool a WETH allowance, and any already-approved pool can pull its own ERC20 from the Facade during `provideFrom` because the pool, not the helper, decides which token is transferred at line 350.

**Impact:** An attacker can use a fake pool to steal any WETH already sitting in the Facade, or use the ETH helper against an already-approved non-WETH pool to spend Facade-held pool tokens and mint LP positions for themselves. Combined with the Facade’s other balance-stranding bugs, this creates a realistic path to drain trapped balances into attacker-owned liquidity or outright theft.

**Paths:**

- Deploy a malicious `IHegicPool` and call `provideEthToPool` with dust ETH; the Facade wraps ETH, approves the fake pool for WETH, and the fake pool uses `transferFrom` to drain any WETH balance held by the Facade.

- For a legitimate non-WETH pool that has already been approved via `poolApprove`, wait until the Facade holds some of that pool token, then call `provideEthToPool(pool, ...)` with `msg.value` equal to the desired raw token amount.

- `HegicPool.provideFrom` pulls `amount` units of the pool’s own `token` from the Facade at line 350, so the attacker receives tranche ownership funded by balances the Facade was already holding.

*Round 1 | Agents: codex, merge-review*

---

## Medium (7)

### F-002: Settlement fees are permanently stranded if rewards are distributed before any staking supply exists

**Confidence:** high | **Locations:** `0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/HegicStaking.sol:231, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/HegicStaking.sol:232, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/HegicStaking.sol:233, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/HegicStaking.sol:235, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:225, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/SettlementFeeDistributor.sol:58`

`HegicStaking.distributeUnrealizedRewards()` increments `realisedBalance` before verifying that any microlots or staking lots exist. If `microLotsTotal + totalSupply() == 0`, the incoming fees are marked as realized without updating either profit accumulator, so they become unclaimable forever.

**Impact:** Settlement fees collected before the first staker or microlot holder joins are permanently lost from the staking system. This causes direct protocol fee loss and breaks the intended fee distribution for early option sales.

**Paths:**

- An option sale forwards settlement fees to the staking contract directly or through `SettlementFeeDistributor`.

- `distributeUnrealizedRewards()` is called while both `microLotsTotal` and `totalSupply()` are zero.

- The tokens are absorbed into `realisedBalance`, but no claimant accounting is updated, so future stakers cannot ever claim them.

*Round 1 | Agents: codex*

---

### F-003: Active option premiums are excluded from NAV, letting late LPs buy underpriced shares

**Confidence:** high | **Locations:** `0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:220, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:304, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:330, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:416`

Option premium is transferred into the pool immediately when an option is sold, but `totalBalance` is not increased until `_unlock()` runs on exercise or expiry. Because LP shares are minted and redeemed against `totalBalance`, deposits made while options are active ignore already-earned premium sitting in the contract.

**Impact:** Strategic late LPs can buy shares at a stale, discounted NAV and capture part of premium already earned by incumbent LPs. This dilutes existing providers and creates a repeatable timing-based value extraction strategy.

**Paths:**

- Existing LPs underwrite options and premium is transferred into the pool contract.

- Before those options are exercised or expired, a new LP deposits and receives shares priced only from stale `totalBalance`.

- When `_unlock()` later credits the premium into `totalBalance`, the new LP owns part of previously earned premium they did not underwrite.

*Round 1 | Agents: codex*

---

### F-011: Exact-output option swaps keep unused user input in the Facade

**Confidence:** high | **Locations:** `onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:149, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:156, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:166, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Facade/Facade.sol:174`

`createOption` pulls the full quoted `optionPrice` from the buyer, executes `swapTokensForExactTokens(rawOptionPrice, optionPrice, ...)`, and never refunds `optionPrice - actualAmountIn` when the router spends less than the max input.

**Impact:** Users overpay whenever the exact-output swap clears below the quoted maximum. The excess tokens become unrecoverable dust inside the Facade, creating permanent user loss and building balances that can later be stolen through other Facade approval/accounting bugs.

**Paths:**

- User calls `createOption` with a swap path longer than one hop.

- The Facade transfers the full quoted `optionPrice` from the user before swapping.

- The router spends only the actual amount needed to obtain `rawOptionPrice` of the pool token.

- The leftover input tokens remain stranded in the Facade because no refund path exists after `pool.sellOption` completes.

*Round 1 | Agents: codex, merge-review*

---

### F-014: Zero-value staking-token transfers can indefinitely reset other users' lockups

**Confidence:** high | **Locations:** `onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC20/ERC20.sol:111, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/@openzeppelin/contracts/token/ERC20/ERC20.sol:227, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/HegicStaking.sol:152, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/HegicStaking.sol:208, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/HegicStaking.sol:216, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/HegicStaking.sol:223, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/HegicStaking.sol:250`

`HegicStaking._beforeTokenTransfer` copies the sender's `lastBoughtTimestamp` to the recipient whenever the sender is still in lockup, but it does not require `amount > 0`. OpenZeppelin ERC20 still executes `_beforeTokenTransfer` for zero-value transfers, so any locked staker can call `transfer(victim, 0)` and refresh the victim's staking-lot cooldown without giving up tokens.

**Impact:** Attackers can cheaply and repeatedly block arbitrary staking-lot holders from calling `sellStakingLot`, creating a permissionless denial of service on exits. Because the attack only needs zero-value transfers, the victim can be kept locked indefinitely unless they proactively opt into rejecting locked transfers.

**Paths:**

- An attacker acquires or receives at least one still-locked staking token position.

- Before the victim exits, the attacker calls `transfer(victim, 0)`.

- ERC20 routes the zero transfer through `_beforeTokenTransfer`, and `HegicStaking` copies the attacker's fresh `lastBoughtTimestamp` onto the victim.

- `sellStakingLot` then reverts under `lockupFree`, and the attacker can repeat the zero-transfer whenever the victim's lockup is about to expire.

*Round 1 | Agents: codex, merge-review*

---

### F-103: Bonding-curve trades lack slippage protection and are easy to sandwich

**Confidence:** high | **Locations:** `onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/ETHBondingCurve.sol:53, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/ETHBondingCurve.sol:64, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/Erc20BondingCurve.sol:56, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/Erc20BondingCurve.sol:71, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/Linear.sol:34`

Both bonding-curve contracts compute price directly from the mutable public `soldAmount` state immediately before execution, but the trading functions expose no user-supplied max-cost or min-refund parameter. As a result, any mempool observer can move `soldAmount` right before a victim trade and force the victim to execute at a materially worse price, especially on ERC20 buys and on all sells.

**Impact:** MEV searchers can systematically extract value from bonding-curve traders by worsening the curve price just before execution and reversing afterward. Victims either overpay, receive too little on exit, or must overprovision their ETH input to avoid reverts, making the curve economically unsafe in a public mempool.

**Paths:**

- Front-run a victim `buy` with another `buy`, increasing `soldAmount`; the victim’s trade now clears at a higher curve price, and the attacker back-runs with `sell` to capture the spread minus commission.

- Front-run a victim `sell` with another `sell`, lowering `soldAmount`; the victim receives a smaller refund, and the attacker back-runs with `buy` to restore their position at the victim’s expense.

*Round 1 | Agents: codex, merge-review*

---

### F-201: Reserve accounting assumes exact ERC20 transfers, enabling short-transfer undercollateralization and reserve drains

**Confidence:** medium | **Locations:** `onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:220, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:342, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/HegicStaking.sol:107, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/HegicStaking.sol:140, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/Erc20BondingCurve.sol:61, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/Erc20BondingCurve.sol:79, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/BondingCurve/ETHBondingCurve.sol:72`

Across the pool, staking, and bonding-curve contracts, internal balances, shares, lots, or sold inventory are credited from the requested transfer amount rather than the tokens actually received. If any configured ERC20 is fee-on-transfer, rebasing-down on transfer, or otherwise short-transfers, users can obtain full-value positions while delivering less value than the contracts account for.

**Impact:** If a non-standard token is ever used, LPs can mint excess pool shares and later withdraw more than they contributed, option buyers can create positions whose recorded premium exceeds the premium actually received, stakers can mint full lots/microlots at a discount and siphon principal plus rewards, and bonding-curve sellers can receive refunds priced as if they returned more tokens than the curve actually received. The result is reserve inflation and eventual losses for honest LPs, stakers, or curve counterparties.

**Paths:**

- Pool deposit path: provide a short-transfer pool token through `provideFrom`; `totalBalance` and tranche share increase by nominal `amount`, then withdraw later against honest liquidity.

- Option sale path: buy with a short-transfer pool token; `sellOption` stores the full `premium`, and `_unlock` later credits that full value into `totalBalance` although less premium reached the pool.

- Staking path: buy a microlot or staking lot with a short-transfer HEGIC token; the full stake balance is minted or credited, then later redeemed for more HEGIC and rewards than was deposited.

- Bonding-curve path: sell a short-transfer `saleToken` into `Erc20BondingCurve` or `ETHBondingCurve`; the contract receives less than `tokenAmount` but still pays the refund computed from the full nominal amount.

*Round 1 | Agents: codex, merge-review*

---

### F-202: PriceCalculatorUtilization uses raw option size instead of put collateral, mispricing put-pool utilization

**Confidence:** medium | **Locations:** `onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Options/PriceCalculatorWtihUtilizationRate.sol:118, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Options/PriceCalculatorWtihUtilizationRate.sol:138, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPut.sol:80`

`PriceCalculatorUtilization` increases utilization with `pool.lockedAmount() + amount`, but put pools measure collateral in quote-token units via `HegicPUT._calculateLockedAmount(amount)`. For puts, `amount` is the option size while `lockedAmount` and `totalBalance` track quote-token collateral, so the pricing formula mixes different units instead of using the collateral that the pool will actually lock.

**Impact:** When this calculator is assigned to a put pool, the utilization surcharge becomes materially wrong. For common high-priced underlyings it can significantly understate real collateral usage and undercharge large puts, letting traders buy more downside protection than the utilization model intends and shifting losses onto LPs; in other deployments it can also overcharge or wrongly reject trades.

**Paths:**

- Attach `PriceCalculatorUtilization` to a `HegicPUT` pool.

- Buy large puts while the pool already has substantial locked collateral.

- Because the calculator adds raw `amount` instead of the quote-token collateral computed by `HegicPUT._calculateLockedAmount`, utilization-based premium adjustment diverges from the pool’s true collateral usage and the put is mispriced.

*Round 1 | Agents: codex, merge-review*

---

## Low (3)

### F-007: Invalid settlement-fee shares can be stored and later brick distributions

**Confidence:** high | **Locations:** `0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/SettlementFeeDistributor.sol:42, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/SettlementFeeDistributor.sol:51, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/SettlementFeeDistributor.sol:63, 0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Staking/SettlementFeeDistributor.sol:64`

`setShares()` validates `stakingShare_ <= totalShare` against the old stored `totalShare` instead of the new `totalShare_`. This allows the owner to save a configuration where `stakingShare > totalShare_`, after which `amount - stakingAmount` underflows during distribution.

**Impact:** A bad share update can halt settlement-fee distribution and make option purchases revert whenever the pool forwards fees to the distributor. The issue is owner-triggered, but the invalid stored state directly causes a protocol DoS until corrected.

**Paths:**

- While the old `totalShare` is still large enough, call `setShares()` with a smaller `totalShare_` but a larger `stakingShare_` than that new total.

- The invalid pair is stored successfully.

- The next `distributeUnrealizedRewards()` computes `stakingAmount > amount`, causing the HLTP transfer amount to underflow and revert.

*Round 1 | Agents: codex*

---

### F-013: Anyone can force early exercise through the public Exerciser once it is approved

**Confidence:** high | **Locations:** `onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Exerciser.sol:37, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Exerciser.sol:41, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Exerciser.sol:44, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPool.sol:254, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Options/OptionsManager.sol:86`

`Exerciser.exercise` is completely public and relies only on the Exerciser contract itself being approved for the option NFT. Once a holder approves this helper, any third party can call it during the final 30 minutes before expiry and satisfy the pool's approval check via the helper contract's own approved status.

**Impact:** Third parties can grief option holders by exercising at the earliest profitable moment in the last 30 minutes, capping any remaining upside that the holder expected to keep until closer to expiry. The funds still go to the rightful owner, but the holder loses timing control after approving the helper.

**Paths:**

- A holder approves the `Exerciser` contract for an option token.

- The option becomes in the money during the final 30 minutes before expiry.

- Any external account calls `Exerciser.exercise(optionId)`, and the pool accepts the call because the approved spender is the helper contract rather than the external caller.

*Round 1 | Agents: codex, merge-review*

---

### F-203: AdaptivePutPriceCalculator hardcodes quote-token and oracle decimals, creating silent mispricing on non-standard deployments

**Confidence:** medium | **Locations:** `onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Options/AdaptivePriceCalculator.sol:99, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Options/AdaptivePriceCalculator.sol:120, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPut.sol:60, onchain_auto/0x7094e706e75e13d1e0ea237f71a7c4511e9d270b/contracts/Pool/HegicPut.sol:86`

`AdaptivePutPriceCalculator` hardcodes `TokenDecimals = 1e6` and divides by `1e8` for the price feed, while `HegicPUT` itself is parameterized by arbitrary `tokenDecimals` and reads `priceProvider.decimals()`. The calculator therefore stops matching the pool’s real collateral math as soon as the quote asset is not 6 decimals or the oracle is not 8 decimals.

**Impact:** If deployed with a non-6-decimal quote token or a non-8-decimal oracle, utilization-based pricing is off by orders of magnitude. That can silently overcharge users, undercharge risk to LPs, or incorrectly reject or accept trades depending on the direction of the decimal mismatch.

**Paths:**

- Deploy `AdaptivePutPriceCalculator` for a put pool whose quote token is not 6 decimals or whose oracle answer is not 8 decimals.

- The calculator computes `_lockedAmount` with its hardcoded constants instead of the pool’s configured decimals.

- Utilization-based premium adjustment diverges from the pool’s actual collateral units, producing materially incorrect option pricing.

*Round 1 | Agents: codex, merge-review*

---
