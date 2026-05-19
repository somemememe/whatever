# Merge View - Round 1

## Summary
- total findings: 6
- new findings: 6
- updated existing findings: 0
- rejected candidates: 9

## Finding Actions
- exact_agent_candidate: 4
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1 | Dev fee is double-counted, minting reflected balance to the contract on every taxed transfer | codex_1:0.619 Dev-fee tokens are minted from thin air on every taxed transfer |
| F-002 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Cooldown is keyed by `sender`, enabling a market-wide 60 second buy denial of service | codex_1:0.84 Cooldown is keyed by sender, causing a global 60-second buy denial of service |
| F-003 | exact_agent_candidate | High | high | codex_1,opencode_1 | Owner can blacklist the LP pair and freeze all trading | codex_1:0.9 Owner can blacklist the LP pair and permanently freeze all trading |
| F-004 | exact_agent_candidate | Medium | high | codex_1 | Ownership can be made to look renounced and later reclaimed | codex_1:1.0 Ownership can be made to look renounced and later reclaimed |
| F-005 | exact_agent_candidate | Medium | medium | codex_1 | Forced full-balance auto-swaps use `amountOutMin = 0`, making them trivially sandwichable | codex_1:1.0 Forced full-balance auto-swaps use `amountOutMin = 0`, making them trivially sandwichable |
| F-006 | exact_agent_candidate | Medium | high | codex_1 | A reverting or gas-heavy team wallet can turn auto-swap into a sell-side denial of service | codex_1:0.857 A bad team wallet can turn auto-swap into a sell-side denial of service |

## Rejection Reasons
- other: 6
- trust_or_owner_model: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Owner can drain all tokens via manualSwap | `manualSwap()` only swaps tokens already held by the contract from fees; it does not let the owner seize arbitrary user balances. This is an admin fee-handling function, not a separate exploit. |
| trust_or_owner_model | opencode_1 | Owner can change charity wallet to steal funds | Changing the fee recipient is an explicit owner-controlled parameter of the fee system. By itself this is centralization/trust risk, not an unintended vulnerability distinct from the retained-admin findings. |
| other | opencode_1 | Sniper list can be abused to block any address | Overstated as written: `_transfer()` checks `recipient` and `msg.sender`, not `sender`, so a blacklisted holder can still move tokens out via `transferFrom` through a non-blacklisted spender such as the router. The stronger pair-freeze variant is retained separately. |
| other | opencode_1 | Transaction limits can be fully removed by owner | `_maxTxAmount` is never enforced anywhere in `_transfer()`, so changing or removing it has no effect and does not introduce a new exploit path. |
| trust_or_owner_model | opencode_1 | UniswapOnly restriction can be disabled | `_removeDestLimit()` is an explicit owner toggle for an anti-bot restriction. Disabling that restriction is an intended admin action, not a standalone vulnerability. |
| other | opencode_1 | Reflection rate calculation may underflow | The cited `rSupply < _rTotal.div(_tTotal)` check is the standard RFI-style fallback guard in `_getCurrentSupply()`. No concrete underflow or exploitable mis-accounting was demonstrated from this condition itself. |
| other | opencode_1 | Missing event logs for critical functions | Missing events are a transparency issue, but not a realistic protocol-level vulnerability causing theft, insolvency, lockup, or denial of service. |
| other | opencode_1 | Division in reflection calculation may lose precision | Integer truncation on fee calculations is expected Solidity behavior and does not create meaningful exploitable harm here. |
| other | opencode_1 | Block timestamp can be manipulated by miner | This is a generic blockchain property and does not materially change the already-retained cooldown flaw or create a separate reportable issue in this contract. |
