# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- exact_agent_candidate: 5

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | High | high | codex_1 | Permissionless fee liquidation uses `amountOutMin = 0`, enabling MEV to drain protocol fee value | codex_1:1.0 Permissionless fee liquidation uses `amountOutMin = 0`, enabling MEV to drain protocol fee value |
| F-002 | exact_agent_candidate | Medium | medium | codex_1,opencode_1 | Public reward conversion can be sandwiched to siphon pending DAI rewards | codex_1:0.937 Public reward conversion can be sandwiched to steal pending DAI rewards |
| F-003 | exact_agent_candidate | Medium | medium | codex_1 | Unbounded slippage escalation can permanently brick reward conversions | codex_1:1.0 Unbounded slippage escalation can permanently brick reward conversions |
| F-004 | exact_agent_candidate | Medium | low | codex_1 | Per-asset rounding in `bond` can mint undercollateralized index supply | codex_1:0.922 Per-asset rounding in `bond` can undercollateralize minted index supply |
| F-005 | exact_agent_candidate | Low | high | codex_1,opencode_1 | Anyone can sweep stray ETH and unsupported ERC20s to an external owner address | codex_1:1.0 Anyone can sweep stray ETH and unsupported ERC20s to an external owner address |

## Rejection Reasons
- other: 6
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Reentrancy vulnerability in flash loan function | The report is too generic. `flash()` only checks that the borrowed token balance is restored after the callback, and no concrete reentrant path was identified that lets the borrower keep protocol assets while still satisfying that post-condition. |
| other | opencode_1 | Fee-on-transfer token input validation bypass | `_transferAndValidate` requires the contract balance to increase by at least `_amount`; fee-on-transfer tokens increase the balance by less than `_amount` and therefore revert instead of bypassing validation. |
| other | opencode_1 | Missing pair existence check in price oracle functions | The missing zero-address check is only on public/view pricing helpers. In this codebase those helpers are not used by state-changing fund flows, so the candidate does not show realistic protocol-level harm. |
| unsupported_or_speculative | opencode_1 | Missing nonReentrant guard on stake function allows reentrancy | If `safeTransferFrom` fails, the entire transaction reverts and the earlier mint is rolled back. The staking token is also the Uniswap V2 pair created in the constructor, so the claimed callback-driven reentrancy surface is unsupported. |
| other | opencode_1 | Unchecked return value in _feeSwap function | The invoked Uniswap V2 router function does not return a value. Failures revert rather than returning a falsey status, so there is no unchecked return-value bug here. |
| other | opencode_1 | TWAP price can be stale or manipulated | This is a generic oracle-quality concern without a concrete exploitable flaw in the provided contracts. The utility implementation is not present, and the candidate does not establish a specific protocol-harming bug beyond normal market/oracle assumptions. |
| other | opencode_1 | Division by zero potential in getIdxPriceUSDX96 | `10 ** decimals()` does not divide by zero when `decimals()` is zero; it becomes 1. The report also does not show a realistic path for `q1` to be zero in a deployed basket beyond pathological configuration. |
| unsupported_or_speculative | opencode_1 | Insufficient input validation in bond function | `bond` already rejects unsupported tokens, and `_amount = 0` does not create a realistic exploit. This is at most an input-sanity issue with no protocol-level impact. |
