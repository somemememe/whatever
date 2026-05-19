# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 3

## Finding Actions
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Anyone can replace the registry and grant themselves mint authority | codex_1:0.847 Anyone can replace the registry and grant themselves unlimited minting rights |
| F-002 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Configured `maxSupply` is never enforced, so the token cap is meaningless | codex_1:0.562 The declared `maxSupply` cap is never enforced, so BBT can exceed its supposed hard cap |
| F-003 | rewritten_agent_signal | High | low | codex_1 | The proxy deployment would be first-caller capturable if it was deployed without initialization calldata | codex_1:0.384 Uninitialized upgradeable deployments can be captured by the first caller |

## Rejection Reasons
- duplicate_or_subsumed: 1
- other: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Hardcoded Owner Address Creates Single Point of Failure | This is a centralization concern, not a standalone exploitable bug, and in this codebase `maxSupply` is never enforced anyway, so controlling `setMaxSupply()` does not directly affect token behavior. |
| other | opencode_1 | Token Name and Symbol Mismatch with ERC20 Standard | This is a metadata inconsistency, not a protocol-level security issue causing fund loss, insolvency, lockup, or realistic DoS. |
| duplicate_or_subsumed | opencode_1 | Registry getContractAddress Reverts Instead of Returning Safe Default | Failing closed on unknown keys is expected behavior. Any mint DoS from a bad registry is already subsumed by the unrestricted `setRegistry()` issue; without that, this mainly reflects owner misconfiguration rather than an independent exploit. |
