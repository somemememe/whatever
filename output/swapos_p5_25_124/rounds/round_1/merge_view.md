# Merge View - Round 1

## Summary
- total findings: 2
- new findings: 2
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | Broken swap invariant allows draining nearly an entire reserve for dust-sized input | codex_1:0.81 Broken swap invariant allows draining about 99% of a reserve for dust input |
| F-002 | rewritten_agent_signal | Low | low | codex_1,opencode_1 | Pair token bindings remain mutable if the factory ever re-calls `initialize()` | codex_1:0.465 Pair can be reinitialized after deployment because `initialize()` is not one-time |

## Rejection Reasons
- other: 10

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Protocol fee formula over-mints LP shares to `feeTo` | The code explicitly documents a `1/2th` sqrt(k) fee at line 88 and the implementation matches that comment. Without contrary protocol specs, this is an economic design choice rather than a demonstrated vulnerability. |
| other | opencode_1 | Division by Zero in Price Oracle Calculation | `_update()` only calls `uqdiv()` inside `if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0)`, so zero reserves do not trigger division by zero. |
| other | opencode_1 | Unprotected skim Function Allows Anyone to Drain Excess Tokens | `skim()` only transfers balances above the recorded reserves. This is standard Uniswap V2 behavior for recovering accidental excess tokens and does not let callers drain accounted LP reserves. |
| other | opencode_1 | Unprotected sync Function Allows Reserve Manipulation | `sync()` merely updates reserves to actual token balances. Any reserve change requires the caller to first move real tokens into the pair, so this is standard spot-price/oracle manipulation, not a standalone pair vulnerability. |
| other | opencode_1 | IERC20 Interface Incompatibility with Non-Standard ERC20 Tokens | The provided pair code only uses `balanceOf` and transfer-style calls; it never calls `name()`, `symbol()`, or `decimals()` on the underlying tokens. The optional metadata declarations in `IERC20` are inert here. |
| other | opencode_1 | Missing Zero Address Validation | Only the factory can set `token0`/`token1`, so zero-address initialization is a trusted-factory misuse case. Zero-address approval/transfer behavior on the LP token does not create third-party theft or protocol-level breakage. |
| other | opencode_1 | K Check Uses Integer Division Losing Precision | The report misdiagnoses the issue. The real problem is the 10000-vs-1000 scaling mismatch in the invariant constant, not ordinary integer precision loss. |
| other | opencode_1 | Permit Function Allows Exact Deadline Timestamp | `deadline >= block.timestamp` is standard permit semantics and does not create meaningful exploitability. |
| other | opencode_1 | Swap Callback Allows Arbitrary Data Execution | The callback is the intended flash-swap hook. Reentrancy into pair state is blocked by `lock`, and no invariant bypass beyond the separate K-check bug is shown. |
| other | opencode_1 | Fee On/Off Logic Can Leave Stale kLast Value | Resetting `kLast` to zero when fees are off is standard Uniswap V2 behavior; re-enabling fees starts a new accounting baseline rather than creating an over-minting bug by itself. |
