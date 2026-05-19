# Merge View - Round 1

## Summary
- total findings: 2
- new findings: 2
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- rewritten_agent_signal: 2

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex | Offer creation stores the real order under a hidden ID while every public interface returns and emits `0` | codex:0.72 New orders are created under a hidden ID while every public API returns and logs `0` |
| F-002 | rewritten_agent_signal | Medium | high | codex | Using Solidity `transfer` for ETH payouts lets contract wallets permanently lock or DOS ETH-backed trades | codex:0.724 Using `transfer` for ETH settlement lets contract wallets permanently DOS fills and refunds |

## Rejection Reasons
- unsupported_or_speculative: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | codex | The market blindly trusts a hardcoded external token address without validating chain or code identity | This depends on deploying the contract onto a wrong or unsupported chain where a different contract exists at the hardcoded address. That is a deployment/configuration mistake rather than an exploit against the intended deployment, so it is not a reportable protocol bug here. |
| unsupported_or_speculative | codex | Settlement never verifies token balance deltas, so non-exact ERC20 transfers can break collateralization | The contract is hardwired to a specific HEX token address rather than accepting arbitrary ERC20s. Without the separate wrong-chain assumption, fee-on-transfer or deflationary-token behavior is not supported by the codebase evidence, so this is not an independent reportable issue. |
