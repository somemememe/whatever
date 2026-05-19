You are auditing the smart contracts in /Users/lu/Desktop/Red_V1G/iZiSwap-core/contracts.

## Contracts in Scope

# Scope

- flash.sol:FlashModule (167 LOC) — TODO
- flash.sol:Point (167 LOC) — TODO
- flash.sol:State (167 LOC) — TODO
- flash.sol:of (167 LOC) — TODO
- iZiSwapFactory.sol:iZiSwapFactory (138 LOC) — TODO
- iZiSwapFactory.sol:address (138 LOC) — TODO
- iZiSwapPool.sol:iZiSwapPool (559 LOC) — TODO
- iZiSwapPool.sol:Point (559 LOC) — TODO
- iZiSwapPool.sol:State (559 LOC) — TODO
- iZiSwapPool.sol:of (559 LOC) — TODO
- interfaces/IERC20Minimal.sol:for (53 LOC) — TODO
- interfaces/IERC20Minimal.sol:that (53 LOC) — TODO
- interfaces/IERC20Minimal.sol:IERC20Minimal (53 LOC) — TODO
- interfaces/IOwnable.sol:IOwnable (9 LOC) — TODO
- interfaces/IiZiSwapCallback.sol:IiZiSwapMintCallback (54 LOC) — TODO
- interfaces/IiZiSwapCallback.sol:IiZiSwapCallback (54 LOC) — TODO
- interfaces/IiZiSwapCallback.sol:IiZiSwapAddLimOrderCallback (54 LOC) — TODO
- interfaces/IiZiSwapFactory.sol:IiZiSwapFactory (100 LOC) — TODO
- interfaces/IiZiSwapFlashCallback.sol:IiZiSwapFlashCallback (17 LOC) — TODO
- interfaces/IiZiSwapPool.sol:IiZiSwapPool (542 LOC) — TODO
- interfaces/IiZiSwapPool.sol:function (542 LOC) — TODO
- interfaces/IiZiSwapPool.sol:function (542 LOC) — TODO
- libraries/AmountMath.sol:AmountMath (49 LOC) — TODO
- libraries/Converter.sol:Converter (11 LOC) — TODO
- libraries/LimitOrder.sol:LimitOrder (19 LOC) — TODO
- libraries/Liquidity.sol:Liquidity (74 LOC) — TODO
- libraries/LogPowMath.sol:LogPowMath (335 LOC) — TODO
- libraries/MaxMinMath.sol:MaxMinMath (34 LOC) — TODO
- libraries/MulDivMath.sol:MulDivMath (82 LOC) — TODO
- libraries/Oracle.sol:Oracle (257 LOC) — TODO
- libraries/OrderOrEndpoint.sol:OrderOrEndpoint (16 LOC) — TODO
- libraries/Point.sol:Point (160 LOC) — TODO
- libraries/PointBitmap.sol:PointBitmap (162 LOC) — TODO
- libraries/State.sol (21 LOC) — TODO
- libraries/SwapCache.sol (24 LOC) — TODO
- libraries/SwapMathX2Y.sol:SwapMathX2Y (248 LOC) — TODO
- libraries/SwapMathX2YDesire.sol:SwapMathX2YDesire (234 LOC) — TODO
- libraries/SwapMathY2X.sol:SwapMathY2X (222 LOC) — TODO
- libraries/SwapMathY2XDesire.sol:SwapMathY2XDesire (213 LOC) — TODO
- libraries/TokenTransfer.sol:TokenTransfer (18 LOC) — TODO
- libraries/TwoPower.sol:TwoPower (9 LOC) — TODO
- libraries/UserEarn.sol:UserEarn (219 LOC) — TODO
- limitOrder.sol:LimitOrderModule (409 LOC) — TODO
- limitOrder.sol:Point (409 LOC) — TODO
- limitOrder.sol:State (409 LOC) — TODO
- limitOrder.sol:of (409 LOC) — TODO
- liquidity.sol:LiquidityModule (473 LOC) — TODO
- liquidity.sol:Point (473 LOC) — TODO
- liquidity.sol:State (473 LOC) — TODO
- liquidity.sol:of (473 LOC) — TODO
- swapX2Y.sol:SwapX2YModule (500 LOC) — TODO
- swapX2Y.sol:Point (500 LOC) — TODO
- swapX2Y.sol:State (500 LOC) — TODO
- swapX2Y.sol:of (500 LOC) — TODO
- swapY2X.sol:SwapY2XModule (445 LOC) — TODO
- swapY2X.sol:Point (445 LOC) — TODO
- swapY2X.sol:State (445 LOC) — TODO
- swapY2X.sol:of (445 LOC) — TODO
- test/TestAddLimOrder.sol:TestAddLimOrder (97 LOC) — TODO
- test/TestCalc.sol:TestCalc (114 LOC) — TODO
- test/TestFlash.sol:TestFlash (127 LOC) — TODO
- test/TestMint.sol:TestMint (106 LOC) — TODO
- test/TestMulDivMath.sol:TestMulDivMath (26 LOC) — TODO
- test/TestPreComputePoolAddress.sol:TestPreComputePoolAddress (28 LOC) — TODO
- test/TestQuoter.sol:TestQuoter (214 LOC) — TODO
- test/TestStorageGas.sol:StorageGasTest (82 LOC) — TODO
- test/TestSwap.sol:TestSwap (222 LOC) — TODO
- test/TestTickMath.sol:TestLogPowMath (31 LOC) — TODO
- test/Token.sol:Token (37 LOC) — TODO
- test/Token.sol:TokenDecimal (37 LOC) — TODO

# Notes

- Auto-generated contract-level map.
- Descriptions are placeholders and can be edited later.


## Known Findings (do NOT repeat — find NEW issues)

- F-001: Output transfers silently underdeliver with fee-on-transfer or deceptive ERC20s (Low, high)
- F-002: collect() and collectLimOrder() erase unpaid claims instead of reverting on shortfalls (Medium, high)
- F-003: enableFeeAmount() allows fee-tier parameters that disable core pool functionality (Low, high)
- F-004: Unbounded defaultFeeChargePercent can make newly created pools revert on fee distribution (Low, high)
- F-005: test/TestAddLimOrder.payCallback() lets arbitrary callers pull approved tokens from the encoded payer (Low, high)
- F-006: Permissionless pool creation lets attackers permanently squat pair/fee slots and choose the initial price (Medium, high)
- F-007: Same-point limit orders settle by first claim rather than order time (Medium, high)
- F-008: Crossing resting limit orders via addLimOrder bypasses swap fee accounting (Low, medium)

## Task

Find security vulnerabilities in the contracts listed above as more as you can.

You should look for:
- vulnerabilities
- reportable issues

If you identify a problem that is not fully proven, still report it as a low-confidence finding.

## Output Format

Return ONLY a JSON array.

Each element must have:
- `id`: local finding id such as `F-001`
- `severity`: `Critical` / `High` / `Medium` / `Low` / `Informational`
- `confidence`: `high` / `medium` / `low`
- `title`: one-line summary
- `locations`: array of `file:line`
- `claim`: core mechanism statement
- `impact`: why it matters
- `paths`: array of trigger/exploit paths, may be empty

If there are no findings, return `[]`.
