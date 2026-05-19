# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 6

## Finding Actions
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | Derivative unwinds and mint accounting use whole-contract balances instead of the current zap's deltas | codex_1:0.54 Minting uses the zapper's full token balances instead of per-call deltas |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Final settlement transfers the zapper's entire BMI and USDC balances to the current caller | codex_1:0.768 Final settlement pays the caller the zapper's entire BMI and USDC balances |
| F-003 | rewritten_agent_signal | Medium | high | codex_1 | Curve swap and liquidity legs hardcode zero minimum-output protection | codex_1:0.784 All Curve swaps and liquidity operations execute with zero minimum-output protection |
| F-004 | rewritten_agent_signal | Low | high | codex_1 | `refundDust` does not unwind supported `ySUSD` constituent dust | codex_1:0.477 Dust refund logic ignores non-YearnCRV constituents such as `ySUSD` |

## Rejection Reasons
- other: 6

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Integer Overflow in fromInt Function | False positive. `fromInt` restricts `x` to `[-2^63, 2^63-1]`; shifting that range left by 64 bits stays within `int128` bounds, including `-2^63 << 64 = -2^127`. |
| other | opencode_1 | Integer Overflow in fromUInt Function | False positive. `fromUInt` restricts `x <= 2^63-1`, and `(2^63-1) << 64` still fits within the signed 64.64 fixed-point `int128` range. |
| other | opencode_1 | Integer Overflow in avg Function | False positive. `avg` adds two `int128` values after widening to `int256`; the sum of two `int128` values cannot overflow `int256`. |
| other | opencode_1 | Integer Overflow in gavg Function | False positive. `gavg` multiplies two `int128` values after widening to `int256`; that intermediate product fits within `int256`, so there is no pre-check overflow here. |
| other | opencode_1 | Potential Integer Overflow in mul Function | False positive. `mul` multiplies two widened `int128` values; their product fits in `int256`, so the only relevant bound is the post-shift range check already present. |
| other | opencode_1 | Outdated Solidity Compiler Version | Not reportable as stated. A generic complaint about using Solidity 0.7.x is not a concrete protocol vulnerability without a specific compiler bug affecting reachable code paths. |
