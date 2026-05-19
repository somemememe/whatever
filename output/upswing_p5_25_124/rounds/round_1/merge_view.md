# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 8

## Finding Actions
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex_1 | Zero-value `transferFrom` lets anyone tamper with another user's pressure accounting and force release/halving | codex_1:0.824 Anyone can use zero-value `transferFrom` to tamper with another user's pressure accounting and force settlement |
| F-002 | rewritten_agent_signal | Medium | medium | codex_1 | Pressure settlement uses manipulable spot pair balance and total supply instead of sale-time state | codex_1:0.591 Burn and Steam payout depend on manipulable spot pair balances rather than fixed sale-time data |
| F-003 | rewritten_agent_signal | Low | high | codex_1 | Sell transfers emit a `Transfer` value that does not match actual balance changes | codex_1:0.807 Pair-sale transfers emit a falsified `Transfer` amount that does not match balance changes |

## Rejection Reasons
- other: 4
- trust_or_owner_model: 4

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Unauthorized Steam Token Minting via Owner Privileges | False positive: `Steam` is deployed via `new Steam(...)` inside `UpSwing`, so `Steam._UPS` is the `UpSwing` contract address, not the external deployer. |
| trust_or_owner_model | opencode_1 | Centralized Admin Control with No Timelock | This is a governance/trust assumption, not a distinct code vulnerability in the permissionless protocol logic. |
| trust_or_owner_model | opencode_1 | Missing Zero Address Validation in setUNIv2 | Requires privileged misconfiguration by an allowed address; it does not create an independent permissionless exploit beyond trusted-admin control. |
| other | opencode_1 | Division by Zero in amountPressure | Only reachable if all UPS supply is voluntarily burned away; that is a terminal self-destruction scenario rather than a realistic independent protocol bug. |
| trust_or_owner_model | opencode_1 | Reentrancy Vulnerability in _transfer | The only external call is `sync()` on the configured pair; exploiting reentrancy would require a privileged actor to point `UNIv2` at a malicious contract, so this is not an independent permissionless issue. |
| other | opencode_1 | Integer Overflow in amountPressure with High Leverage | False positive: arithmetic uses `SafeMath`, and `leverage` is a `uint8`, so the proposed >1000 overflow path is not valid. |
| other | opencode_1 | Missing Event Emissions for Critical Functions | Transparency issue only; not a realistic protocol-security vulnerability. |
| trust_or_owner_model | opencode_1 | Leverage Can Be Set to Zero Breaking Protocol | Relies entirely on privileged admin action and is covered by the protocol's trusted-admin model rather than an exploitable bug. |
