# Merge View - Round 1

## Summary
- total findings: 7
- new findings: 7
- updated existing findings: 0
- rejected candidates: 9

## Finding Actions
- exact_agent_candidate: 4
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Standard ERC20 repayments are impossible because the pool uses `transferFrom(address(this), ...)` when forwarding funds | codex_1:0.898 Standard ERC20 repayments are impossible because the pool uses `transferFrom(address(this), ...)` |
| F-002 | rewritten_agent_signal | High | high | merge_review | Repayments between lender-rate and client-rate outstanding can clear the loan without returning collateral | opencode_1:0.368 Repay can result in underflow when repayAmount less than outstanding |
| F-003 | rewritten_agent_signal | High | high | merge_review | PineWallet-backed loans cannot be liquidated consistently | opencode_1:0.481 Missing check for loan existence before liquidation |
| F-004 | exact_agent_candidate | Medium | high | codex_1 | Liquidations permanently consume the global loan cap because `_currentLoanAmount` is never reduced | codex_1:1.0 Liquidations permanently consume the global loan cap because `_currentLoanAmount` is never reduced |
| F-005 | exact_agent_candidate | Medium | high | codex_1 | Collateral can be liquidated without any on-chain unhealthy-loan check | codex_1:1.0 Collateral can be liquidated without any on-chain unhealthy-loan check |
| F-006 | rewritten_agent_signal | Medium | low | codex_1 | Uninitialized pool deployments can be taken over through the public initializer | codex_1:0.533 Any uninitialized pool instance can be seized because the implementation is not locked |
| F-007 | exact_agent_candidate | Medium | high | codex_1 | Anyone can take zero-fee flash loans from any token allowance granted by `_fundSource` | codex_1:0.965 Anyone can take fee-free flash loans from any token allowance granted by `_fundSource` |

## Rejection Reasons
- duplicate_or_subsumed: 1
- factually_incorrect: 2
- other: 3
- trust_or_owner_model: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| factually_incorrect | opencode_1 | Flash loan returns funds without verification, enabling fund theft | Incorrect. The post-loan check at `1607-1650` requires `_fundSource` or the pool to end with exactly the same balance as before when `amountFee == 0`, so the borrower cannot keep the funds. |
| factually_incorrect | opencode_1 | Block-based loan limit can be bypassed within same block | Incorrect. `updateBlockLoanAmount()` adds the new amount first and immediately reverts if the cumulative amount for the current block reaches or exceeds `blockLoanLimit`, so bundling transactions does not bypass the cap. |
| other | opencode_1 | Signature can be replayed across different loans with same parameters | Not independently reportable here. A single NFT cannot hold concurrent loans, and reusing the same valuation for the same NFT before expiry is largely the intended behavior of this verifier. |
| other | opencode_1 | Repay can result in underflow when repayAmount less than outstanding | The claimed arithmetic-underflow path is not the real issue. The actual repayment failure is the outbound `transferFrom(address(this), ...)` bug captured separately. |
| duplicate_or_subsumed | opencode_1 | Missing check for loan existence before liquidation | The specific claim about liquidating already repaid NFTs is incorrect because full repayment transfers the NFT out before loan terms are cleared. The broader liquidation-trust issue is already captured separately. |
| trust_or_owner_model | opencode_1 | No validation that _controlPlane is a valid contract | This is owner/configuration hygiene rather than an intrinsic exploit path in the pool. |
| other | opencode_1 | Precision loss in fee calculations | This is ordinary integer truncation with negligible impact and is not reportable. |
| trust_or_owner_model | opencode_1 | PineWallet clone validation only checks factory whitelist | Insufficient support from the available code. The pool also requires ownership of the derived mirror token, and any exploit would depend on external factory or wallet behavior not shown here. |
| unsupported_or_speculative | codex_1 | Valuation signatures are replayable across pools and borrowing contexts | Too speculative as a standalone issue. The signature appears to authorize valuation data only, while amount and duration are intentionally bounded by pool parameters; concrete cross-pool harm would require extra deployment or signer-reuse assumptions. |
