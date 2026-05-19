# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 0

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex | Fresh debt and replacement borrowers bypass opening collateral-ratio checks | codex:0.494 New debt can be opened or reassigned without enforcing borrower collateral requirements |
| F-002 | exact_agent_candidate | Medium | high | codex | ETH-backed deposits mint against the contract’s full ETH balance instead of the caller’s contribution | codex:0.949 ETH-backed deposits mint against the contract’s full ETH balance, not the caller’s contribution |
| F-003 | rewritten_agent_signal | Medium | high | codex | User-chosen routers in `DexSwap` can drain residual balances from the shared zap contract | codex:0.551 Arbitrary router approvals and calls in `DexSwap` let callers drain residual zap balances |
| F-004 | exact_agent_candidate | Medium | medium | codex | Oracle fails open to an unbounded Uniswap V3 TWAP whenever Chainlink pricing reverts | codex:0.857 Oracle fails open to a manipulable Uniswap V3 TWAP whenever Chainlink reverts |

## Rejection Reasons
- none
