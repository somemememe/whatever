# Merge View - Round 9

## Summary
- total findings: 29
- new findings: 2
- updated existing findings: 0
- rejected candidates: 2

## Finding Actions
- exact_agent_candidate: 2
- existing_preserved: 27

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-301 | exact_agent_candidate | High | medium | codex_1 | Queue creator can pick queue proxy admin and later upgrade into privileged malicious queue logic | codex_1:1.0 Queue creator can pick queue proxy admin and later upgrade into privileged malicious queue logic |
| F-302 | exact_agent_candidate | Medium | high | codex_1 | Signature redeem queue cannot receive ETH transferred from vault hook flow | codex_1:1.0 Signature redeem queue cannot receive ETH transferred from vault hook flow |

## Rejection Reasons
- other: 2

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Lido deposit hook forwards ETH to wstETH address in WETH/ETH branch | Non-reportable as written: this is the intended Lido wstETH integration path (sending ETH to wstETH contract to mint wrapped shares), and existing tests exercise ETH/WETH branches without indicating protocol-level loss semantics. |
| other | codex_1 | OwnedCustomVerifier initializer lacks array length validation | Rejected as non-reportable: mismatched array lengths only cause initialization revert for malformed init payloads, with no realistic fund-loss, privilege-escalation, or persistent DoS vector in normal atomic proxy initialization flow. |
