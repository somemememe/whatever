# Merge View - Round 8

## Summary
- total findings: 27
- new findings: 4
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 3
- existing_preserved: 23
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-201 | exact_agent_candidate | High | high | codex_1 | Tokenized lockup is bypassable via auto-claim ordering in `_update` | codex_1:1.0 Tokenized lockup is bypassable via auto-claim ordering in `_update` |
| F-202 | exact_agent_candidate | Low | medium | codex_1 | Signature deposits bypass depositor whitelist checks on the caller | codex_1:1.0 Signature deposits bypass depositor whitelist checks on the caller |
| F-203 | exact_agent_candidate | Low | high | codex_1 | Blacklist is not enforced for transfer recipients | codex_1:1.0 Blacklist is not enforced for transfer recipients |
| F-204 | rewritten_agent_signal | Low | medium | codex_1 | First report for a newly supported asset is always marked suspicious | codex_1:0.454 New-asset first report is always flagged suspicious, creating hard dependency on `acceptReport` |

## Rejection Reasons
- factually_incorrect: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| factually_incorrect | opencode_1 | BasicRedeemHook.getLiquidAssets uses msg.sender instead of address(this) | In protocol flow `getLiquidAssets` is called by `ShareModule`, so `msg.sender` is intentionally the vault context. Using `address(this)` there would point to the hook contract and return incorrect balances. |
