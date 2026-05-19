# Merge View - Round 6

## Summary
- total findings: 15
- new findings: 2
- updated existing findings: 0
- rejected candidates: 9

## Finding Actions
- existing_preserved: 13
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-014 | rewritten_agent_signal | Low | medium | codex_1 | Whitelisted router can be used as a generic arbitrary-pair vETH redemption adapter | codex_1:0.431 Public rebalance can inject arbitrary bits into the OKX pool descriptor |
| F-015 | rewritten_agent_signal | Low | high | codex_1 | Native ETH accepted by router and rebalancer has no recovery path | codex_1:0.692 Native ETH sent directly to router or rebalancer is unrecoverable |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 4
- trust_or_owner_model: 1
- unsupported_or_speculative: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | LamboToken implementation remains publicly initializable | Initializing the implementation mints tokens only in the implementation contract's own storage and does not affect clones created by the factory. The stated harm depends on off-chain/UI confusion rather than protocol-level loss or corruption. |
| unsupported_or_speculative | codex_1 | Public rebalance can inject arbitrary bits into the OKX pool descriptor | The code does allow unrestricted `directionMask` bits, but the submitted impact is speculative: failed descriptors only revert the caller's rebalance, and successful execution must still pass flash-loan repayment plus the positive WETH profit check. No concrete loss, theft, persistent DoS, or exploitable OKX flag layout was demonstrated. |
| unsupported_or_speculative | opencode_1 | VirtualToken takeLoan has no recipient verification allowing infinite debt accumulation | `takeLoan` is restricted to `validFactories`; the in-scope factory passes only the newly created pair as recipient, and the per-block cap bounds issuance. The candidate assumes a malicious/invalid factory or arbitrary victim recipient not supported by the current call path. |
| unsupported_or_speculative | opencode_1 | VirtualToken repayLoan is permissionless allowing anyone to reduce arbitrary debts | `repayLoan` is not permissionless; it has the same `onlyValidFactory` gate as `takeLoan`. It also checks debt before decreasing and then burns from the debtor, so the claimed arbitrary external accounting manipulation is not supported. |
| duplicate_or_subsumed | opencode_1 | Rebalance amountOut parameter is ignored allowing zero slippage protection | Duplicate of existing F-008. This round did not add a distinct root cause; the suggested High severity is not kept because the rebalance requires positive WETH profit after flash-loan repayment, limiting direct principal loss while still allowing value capture/slippage degradation. |
| trust_or_owner_model | opencode_1 | extractProfit can drain protocol vETH and wrapped tokens | `extractProfit` is owner-only and the owner already controls UUPS upgrade authorization. The candidate is a privileged-owner trust assumption rather than an untrusted exploit path. |
| other | opencode_1 | VirtualToken debt can exceed totalSupply causing accounting inconsistency | `takeLoan` mints the same amount that it records as debt, `_decreaseDebt` requires sufficient debt, and Solidity 0.8 arithmetic prevents silent overflow. No supported sequence was provided that makes debt inconsistent with supply. |
| other | opencode_1 | getBuyQuote and getSellQuote use potentially outdated reserves | The functions are view quote helpers and reserve changes between quote and execution are normal AMM behavior. The state-changing buy/sell functions accept `minReturn`, so this is not a distinct protocol vulnerability. |
| other | opencode_1 | Rebalance uses OKXRouter with hardcoded token approve address | This is an external dependency/configuration risk. The candidate relies on the hardcoded OKX approval contract becoming invalid or compromised, not on an in-scope implementation flaw. |
