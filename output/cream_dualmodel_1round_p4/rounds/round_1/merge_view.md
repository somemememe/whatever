# Merge View - Round 1

## Summary
- total findings: 2
- new findings: 2
- updated existing findings: 0
- rejected candidates: 7

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | Collateral cap is unenforceable for pre-upgrade balances in upgraded collateral-cap markets | codex_1:0.674 Collateral cap is bypassed for legacy balances after upgrading to the collateral-cap implementation |
| F-002 | exact_agent_candidate | Medium | medium | codex_1 | Flash-loan callers can spoof the `initiator` value delivered to receivers | codex_1:0.9 Flashloan callers can spoof the `initiator` value seen by receivers |

## Rejection Reasons
- other: 6
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Incorrect Liquidation Health Check Logic | The extra `shortfall > 0` check runs after `doTransferIn` but before borrow storage is reduced, so it is not validating post-liquidation health. It is a mid-transfer reentrancy defense, not inverted liquidation logic. |
| other | opencode_1 | Flash Loan State Inconsistency Allows Reentrancy | During the callback, `totalBorrows` is temporarily increased but `internalCash` has already been reduced by the same loan amount, preserving core exchange-rate accounting. No concrete exploit path or accounting break was substantiated beyond generic reentrancy speculation. |
| other | opencode_1 | Unprotected gulp() Function Allows Reserve Manipulation | `gulp()` only converts excess underlying already sitting in the contract into reserves. Anyone can already donate tokens to the market, and calling `gulp()` does not create attacker profit, fund loss, or meaningful protocol harm. |
| other | opencode_1 | Missing Access Control on Collateral Cap Setting | `_setCollateralCap` explicitly requires `msg.sender == admin`. This is a style inconsistency at most, not an access-control vulnerability. |
| other | opencode_1 | Unused isNative Parameter in doTransferIn/doTransferOut | Unused parameters are code smell only and do not create a realistic security impact here. |
| unsupported_or_speculative | codex_1 | Liquidation liveness depends on an extra post-transfer liquidity check inside a callback-capable repayment path | This scenario is highly speculative and mainly relies on callback behavior during `transferFrom` to change the borrower's cross-market liquidity mid-transaction. The most direct callback control is with the liquidator/payer, who can already sabotage their own liquidation, so a realistic third-party protocol-level exploit was not established. |
| other | codex_1 | Flashloan callback magic value is non-standard and rejects standard ERC-3156 receivers | The mismatch is a compatibility/integration issue, but by itself it does not show realistic fund loss, theft, insolvency, or durable denial of service for the protocol. It is not sufficiently reportable as a security finding on this record. |
