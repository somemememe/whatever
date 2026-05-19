You are auditing the smart contracts in /Users/lu/Desktop/Red_V1G/iZiSwap-core/contracts.

## Contracts in Scope

# Scope

- flash.sol (167 LOC) — TODO
- iZiSwapFactory.sol (138 LOC) — TODO
- iZiSwapPool.sol (559 LOC) — TODO
- interfaces/IERC20Minimal.sol (53 LOC) — TODO
- interfaces/IOwnable.sol (9 LOC) — TODO
- interfaces/IiZiSwapCallback.sol (54 LOC) — TODO
- interfaces/IiZiSwapFactory.sol (100 LOC) — TODO
- interfaces/IiZiSwapFlashCallback.sol (17 LOC) — TODO
- interfaces/IiZiSwapPool.sol (542 LOC) — TODO
- libraries/AmountMath.sol (49 LOC) — TODO
- libraries/Converter.sol (11 LOC) — TODO
- libraries/LimitOrder.sol (19 LOC) — TODO
- libraries/Liquidity.sol (74 LOC) — TODO
- libraries/LogPowMath.sol (335 LOC) — TODO
- libraries/MaxMinMath.sol (34 LOC) — TODO
- libraries/MulDivMath.sol (82 LOC) — TODO
- libraries/Oracle.sol (257 LOC) — TODO
- libraries/OrderOrEndpoint.sol (16 LOC) — TODO
- libraries/Point.sol (160 LOC) — TODO
- libraries/PointBitmap.sol (162 LOC) — TODO
- libraries/State.sol (21 LOC) — TODO
- libraries/SwapCache.sol (24 LOC) — TODO
- libraries/SwapMathX2Y.sol (248 LOC) — TODO
- libraries/SwapMathX2YDesire.sol (234 LOC) — TODO
- libraries/SwapMathY2X.sol (222 LOC) — TODO
- libraries/SwapMathY2XDesire.sol (213 LOC) — TODO
- libraries/TokenTransfer.sol (18 LOC) — TODO
- libraries/TwoPower.sol (9 LOC) — TODO
- libraries/UserEarn.sol (219 LOC) — TODO
- limitOrder.sol (409 LOC) — TODO
- liquidity.sol (473 LOC) — TODO
- swapX2Y.sol (500 LOC) — TODO
- swapY2X.sol (445 LOC) — TODO
- test/TestAddLimOrder.sol (97 LOC) — TODO
- test/TestCalc.sol (114 LOC) — TODO
- test/TestFlash.sol (127 LOC) — TODO
- test/TestMint.sol (106 LOC) — TODO
- test/TestMulDivMath.sol (26 LOC) — TODO
- test/TestPreComputePoolAddress.sol (28 LOC) — TODO
- test/TestQuoter.sol (214 LOC) — TODO
- test/TestStorageGas.sol (82 LOC) — TODO
- test/TestSwap.sol (222 LOC) — TODO
- test/TestTickMath.sol (31 LOC) — TODO
- test/Token.sol (37 LOC) — TODO

# Notes

- Auto-generated file-level map.
- Descriptions are placeholders and can be edited later.


## Known Findings (do NOT repeat — find NEW issues)

None yet.


## Task

Find security vulnerabilities in the contracts listed above as more as you can.

You should look for:
- vulnerabilities
- reportable issues

If you identify a problem that is not fully proven, still report it as a low-confidence finding.
Do not report documented behavior or pure owner-only configuration issues unless they can realistically cause fund loss, theft, permanent lockup, or permissionless denial of service.

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
