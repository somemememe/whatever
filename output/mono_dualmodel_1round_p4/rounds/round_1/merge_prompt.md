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
    "title": "Self-swaps are allowed, letting an attacker inflate a pool price without spending vCash",
    "locations": [
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:697",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:751",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:807",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:854"
    ],
    "claim": "The swap path never rejects `tokenIn == tokenOut`. For a same-token trade, the contract first applies the sell-side price update, then applies a buy-side price update to the same pool and nets the vCash bookkeeping back out, so the attacker can ratchet the token price upward while only losing a small amount of the same token.",
    "impact": "After inflating an official/supported token's pool price, the attacker can sell that overpriced token for vCash or other assets and drain other pools. This is the core invariant break that lets one pool mint purchasing power out of thin air.",
    "paths": [
      "Call `swapExactTokenForToken(token, token, amountIn, 0, attacker, deadline)` or `swapTokenForExactToken(token, token, amountInMax, amountOut, attacker, deadline)` repeatedly to push `pools[token].price` up with near-zero net vCash cost.",
      "Then swap the now-overpriced token into `vCash`, `WETH`, or any other pooled asset to extract real value."
    ]
  },
  {
    "id": "F-002",
    "severity": "High",
    "confidence": "high",
    "title": "Exact-output swaps undercharge fee-on-transfer tokenIn amounts",
    "locations": [
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:697",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:859",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:863",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:875"
    ],
    "claim": "In `swapOut`, `getAmountIn` computes `amountIn` and `tradeVcashValue` before the transfer, but `transferAndCheck` may later return a smaller actual received amount for fee-on-transfer tokens. The function does not recompute the quote, and still gives the full requested output using the stale `tradeVcashValue`.",
    "impact": "Any supported transfer-tax token used as `tokenIn` can buy too much output for too little input, leaving the pool undercollateralized and allowing attackers to drain target assets or vCash.",
    "paths": [
      "Use `swapTokenForExactToken(feeToken, valuableToken, amountInMax, amountOut, attacker, deadline)` with a transfer-tax `feeToken`.",
      "The protocol prices the swap as if the full quoted `amountIn` arrived, but only the post-tax amount reaches `monoXPool`."
    ]
  },
  {
    "id": "F-003",
    "severity": "High",
    "confidence": "high",
    "title": "LP lockups can be bypassed by calling `removeLiquidity` through a helper address",
    "locations": [
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:443",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:447",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:452",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:501"
    ],
    "claim": "The time-lock and top-holder checks are keyed off `msg.sender`, but the LP balance that gets withdrawn and burned is taken from `to`. A user can therefore call from a fresh helper contract while setting `to` to the real LP holder, bypassing the 4h/24h/90d restrictions.",
    "impact": "The anti-rug liquidity locks on listed and official pools are not enforceable. A project team or top LP can exit immediately through a helper contract, and third parties can also force-remove someone else's LP position if Monoswap is authorized to burn LP shares on their behalf.",
    "paths": [
      "Address A adds liquidity and holds the LP tokens.",
      "Helper contract B calls `removeLiquidity(token, liquidity, A, 0, 0)`.",
      "The contract checks B's timestamps and holder status, but burns A's LP balance and sends the underlying assets to A."
    ]
  },
  {
    "id": "F-004",
    "severity": "High",
    "confidence": "low",
    "title": "Only `tokenIn` is locked, so a malicious `tokenOut` can reenter before its pool accounting is updated",
    "locations": [
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:84",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:807",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:838",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:840",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:854",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:885",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:887"
    ],
    "claim": "Swaps lock only `tokenIn`, but transfer `tokenOut` out via an external call before `pools[tokenOut]` is synchronized. A malicious ERC20 used as `tokenOut` can reenter Monoswap during its transfer logic while its own pool still exposes stale reserves and price.",
    "impact": "If a malicious token is listed, nested calls can execute against inconsistent state and potentially extract excess vCash or other assets before the outer swap finishes updating the `tokenOut` pool.",
    "paths": [
      "Create or use a pool where `tokenOut` is a malicious ERC20.",
      "Initiate a swap into that token so `safeTransferERC20Token(tokenOut, ...)` executes.",
      "Reenter Monoswap from the token's transfer logic before `_updateTokenInfo(tokenOut, ...)` runs."
    ]
  },
  {
    "id": "F-005",
    "severity": "Medium",
    "confidence": "high",
    "title": "Relisting an unlisted token overwrites its pool id and can strand old LP positions",
    "locations": [
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:219",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:288",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:292",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:452",
      "0x66e7d7839333f502df355f5bd87aea24bac2ee63/contracts/Monoswap.sol:501"
    ],
    "claim": "Setting a pool to `UNLISTED` clears `tokenPoolStatus`, which allows `_createPool` to create a brand new `pid` for the same token and overwrite `pools[_token]`. All later liquidity accounting uses the new `pid`, not the original one held by existing LPs.",
    "impact": "If a token is unlisted and re-listed, holders of the original LP token can become unable to redeem their old position through Monoswap, resulting in permanent fund lockup or broken accounting across two pool ids for one token.",
    "paths": [
      "Owner calls `updatePoolStatus(token, UNLISTED)`.",
      "A new pool for the same `token` is created with `_createPool`, replacing `pools[token].pid`.",
      "Old LP holders can no longer remove liquidity because Monoswap now looks at the new pid."
    ]
  },
  {
    "id": "F-006",
    "severity": "Critical",
    "confidence": "high",
    "title": "UUPS upgrade authorization is completely unrestricted in `Proxiable` / `ChildOfProxiable`",
    "locations": [
      "0xc36a7887786389405ea8da0b87602ae3902b88a1/contracts/test/Proxiable.sol:6",
      "0xc36a7887786389405ea8da0b87602ae3902b88a1/contracts/test/Proxiable.sol:7",
      "0xc36a7887786389405ea8da0b87602ae3902b88a1/contracts/test/Proxiable.sol:14",
      "0xc36a7887786389405ea8da0b87602ae3902b88a1/@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol:17",
      "0xc36a7887786389405ea8da0b87602ae3902b88a1/@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol:22"
    ],
    "claim": "`Proxiable._authorizeUpgrade` performs no access control at all; it only calls `_beforeUpgrade`, and `ChildOfProxiable` leaves that hook empty. Any caller can therefore invoke the inherited UUPS `upgradeTo` / `upgradeToAndCall` functions.",
    "impact": "Any proxy using this implementation can be upgraded to attacker-controlled code and fully taken over, resulting in arbitrary state corruption, asset theft, or permanent bricking.",
    "paths": [
      "Deploy a proxy pointing at `ChildOfProxiable` or any implementation inheriting `Proxiable` without adding its own auth.",
      "Attacker calls `upgradeTo(maliciousImplementation)` or `upgradeToAndCall(...)` through the proxy.",
      "The proxy starts delegating to attacker code."
    ]
  }
]

```

### Agent: opencode_1
```
[{"id":"F-001","severity":"Critical","confidence":"high","title":"Owner Can Drain All Pool Funds via Token Status Manipulation","locations":["Monoswap.sol:198-199","Monoswap.sol:272-277","Monoswap.sol:251-262"],"claim":"The owner can set any token to status=2 (exempt) via setTokenStatus(), which bypasses balance verification in transferAndCheck(). Then by calling rebalancePool(), the owner can transfer the entire token balance from the pool to feeTo address.","impact":"Owner can steal all tokens deposited in any pool by setting token status to exempt and calling rebalancePool(). This results in complete loss of liquidity provider funds.","paths":["1. Owner calls setTokenStatus(token, 2) to set token as exempt","2. Owner calls rebalancePool(token)","3. All tokens in pool are transferred to feeTo address"]},{"id":"F-002","severity":"High","confidence":"high","title":"Missing Zero Address Check for feeTo","locations":["Monoswap.sol:175-177"],"claim":"The setFeeTo() function does not validate that the new fee recipient is not address(0).","impact":"If owner accidentally sets feeTo to address(0), all trading fees become permanently irrecoverable. The protocol loses all fee revenue.","paths":["1. Owner calls setFeeTo(address(0))","2. All trading fees are sent to address(0) and permanently lost"]},{"id":"F-003","severity":"High","confidence":"high","title":"Excessive Fee Setting Allowed","locations":["Monoswap.sol:179-182","Monoswap.sol:184-187"],"claim":"The owner can set fees and devFee up to 10% (1000/10000) without any upper bound enforcement beyond this limit.","impact":"Owner can set extremely high trading fees (up to 10% per swap), causing significant financial harm to users. Combined with ability to change feeTo, this allows complete theft of user funds.","paths":["1. Owner calls setFees(1000) or higher","2. All swaps incur excessive fees harming users"]},{"id":"F-004","severity":"High","confidence":"high","title":"Direct Swap Logic Always Returns False","locations":["Monoswap.sol:684-694","Monoswap.sol:736","Monoswap.sol:791"],"claim":"The directSwapAllowed function uses faulty logic: (tokenInValue/tokenOutValue) + (tokenOutValue/tokenInValue) == 1. This equation only equals 1 when both values are exactly equal, which is essentially impossible due to integer division rounding.","impact":"Direct swaps between pools are effectively disabled despite the code attempting to enable them. This breaks intended AMM functionality and may cause incorrect price calculations.","paths":["1. Any swap that would benefit from directSwapAllowed will fail the condition check"]},{"id":"F-005","severity":"High","confidence":"medium","title":"Owner Can Arbitrarily Change Pool Prices","locations":["Monoswap.sol:230-237"],"claim":"The owner can set any price for any pool after 6000 blocks of inactivity, with no validation that the new price is reasonable or reflects market conditions.","impact":"Owner can manipulate pool prices arbitrarily to liquidate positions, steal LP funds through unfavorable pricing, or cause other economic harm to users.","paths":["1. Wait 6000 blocks without trading on a pool","2. Owner calls updatePoolPrice(token, arbitraryPrice)","3. Users trade at manipulated price"]},{"id":"F-006","severity":"High","confidence":"high","title":"Missing Access Control on Price Adjuster Role","locations":["Monoswap.sol:244-249"],"claim":"The setSynthPoolPrice function can only be called by addresses with priceAdjusterRole, but this role can be granted to any address by the owner with no restrictions.","impact":"A compromised or malicious owner or price adjuster can set arbitrary synthetic pool prices, causing severe economic manipulation and loss of user funds.","paths":["1. Owner calls updatePriceAdjuster(maliciousAddress, true)","2. Malicious price adjuster calls setSynthPoolPrice(token, manipulatedPrice)"]},{"id":"F-007","severity":"High","confidence":"medium","title":"Top LP Removal Restriction Can Be Bypassed","locations":["Monoswap.sol:445-447"],"claim":"The top LP holder cannot remove liquidity within 90 days, but this check only applies when pool status is LISTED. If status changes to OFFICIAL or UNLISTED, the restriction is bypassed.","impact":"A large liquidity provider can avoid the 90-day lockup by having the pool status changed, potentially causing rug-pull scenarios.","paths":["1. Attacker adds massive liquidity to become top LP","2. Pool status changed to OFFICIAL or UNLISTED","3. Attacker removes all liquidity immediately"]},{"id":"F-008","severity":"Medium","confidence":"high","title":"Insufficient Pool Size Validation","locations":["Monoswap.sol:678-679"],"claim":"The check 'initialPoolValue <= poolValue || poolValue >= poolSizeMinLimit' uses OR instead of AND, meaning if either condition is true the transaction passes.","impact":"When poolValue is less than poolSizeMinLimit but greater than initialPoolValue (due to fees), swaps are allowed, potentially allowing pools to shrink below minimum viable size.","paths":["1. Pool starts above minimum size","2. Multiple trades reduce pool value below min limit","3. Swaps still allowed due to OR condition"]},{"id":"F-009","severity":"Medium","confidence":"medium","title":"Token Insurance Not Backed by Actual Collateral","locations":["Monoswap.sol:193-195","Monoswap.sol:656-657"],"claim":"The tokenInsurance mapping can be set by owner to any value without requiring actual collateral to back it. The check only enforces that vcashDebt <= tokenInsurance.","impact":"The insurance mechanism provides a false sense of security. Listed pools require insurance but there's no actual collateral securing it, misleading users about their risk exposure.","paths":["1. Owner sets tokenInsurance[token] to high value without depositing collateral","2. Users believe they are protected but funds are not actually backed"]},{"id":"F-010","severity":"Medium","confidence":"medium","title":"Owner Can Pause Pools Without Time Constraint for Some Transitions","locations":["Monoswap.sol:203-222"],"claim":"The updatePoolStatus function only enforces a 6000 block delay when transitioning FROM PAUSED. Other transitions like PAUSED->UNLISTED do not have the same restriction.","impact":"Owner can unpause a pool after only 6000 blocks but could immediately pause again, allowing rapid status changes that could disrupt trading.","paths":["1. Pool is paused","2. Wait 6000 blocks","3. Change to any other status immediately","4. Immediately pause again - no delay needed"]},{"id":"F-011","severity":"Low","confidence":"high","title":"Rounding Loss in Liquidity Calculations","locations":["Monoswap.sol:385","Monoswap.sol:390","Monoswap.sol:463-466"],"claim":"Multiple division operations in liquidity calculations can cause precision loss, especially with the 1e6 division for initial liquidity calculation.","impact":"Users may receive slightly less liquidity tokens than expected due to rounding, causing minor financial loss.","paths":["1. User adds liquidity with specific amounts","2. Due to division rounding, receives less LP tokens than calculated"]},{"id":"F-012","severity":"Low","confidence":"medium","title":"Uninitialized feeTo Allows Immediate Loss of Fees","locations":["Monoswap.sol:33","Monoswap.sol:175-177"],"claim":"The feeTo variable is not initialized in the constructor or initialize() function, meaning it defaults to address(0).","impact":"Before setFeeTo is called, any fees collected would be sent to address(0) and permanently lost.","paths":["1. Contract deployed","2. Trades occur before setFeeTo is called","3. All fees lost to address(0)"]}]

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
