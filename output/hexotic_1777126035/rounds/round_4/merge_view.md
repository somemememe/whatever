# Merge View - Round 4

## Summary
- total findings: 3
- new findings: 0
- updated existing findings: 0
- rejected candidates: 5

## Finding Actions
- existing_preserved: 3

## New Or Updated Findings
- none

## Rejection Reasons
- other: 4
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| unsupported_or_speculative | codex | Token accounting assumes exact ERC20 transfers and can leave ETH trades underpaid or HEX offers undercollateralized | Speculative for the intended hardcoded HEX token, which is not shown here to be fee-on-transfer or rebasing; if the bound token is malicious or nonstandard on another chain, that risk is already covered by F-003. |
| other | codex | Orders are globally fillable by any observer, so negotiated OTC trades can be sniped before the intended counterparty | This contract implements a public on-chain order book with no taker binding or signature scheme; first-come-first-served fills are the explicit design, not a code-level vulnerability. |
| other | codex | Makers can self-fill their own orders and emit successful trade events without performing a real swap | The behavior can spoof logs, but it does not by itself create realistic protocol-level fund loss, insolvency, lockup, or permissionless DoS in this codebase. |
| other | codex | Directly transferred HEX or forcibly sent ETH can become permanently stranded in the contract | This is a generic accidental-transfer limitation requiring user error or forced ETH; it is not an exploitable protocol bug and does not create meaningful incremental risk beyond standard unsolicited-balance behavior. |
| other | codex | Unchecked `last_offer_id++` can eventually wrap and reuse order IDs | Technically true in Solidity 0.4.x, but practically unreachable and therefore not reportable. |
