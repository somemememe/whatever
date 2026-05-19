# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex | Anyone can steal approved EOA VISR by depositing from the victim into their own share account | codex:1.0 Anyone can steal approved EOA VISR by depositing from the victim into their own share account |
| F-002 | exact_agent_candidate | Critical | high | codex | A fake `IVisor` contract can mint completely unbacked shares and drain all VISR | codex:1.0 A fake `IVisor` contract can mint completely unbacked shares and drain all VISR |
| F-003 | exact_agent_candidate | High | high | codex | The first depositor can seize any VISR already sitting in the hypervisor | codex:1.0 The first depositor can seize any VISR already sitting in the hypervisor |

## Rejection Reasons
- duplicate_or_subsumed: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| duplicate_or_subsumed | codex | Share minting uses the requested deposit amount instead of the actual VISR received | The accounting flaw is real for the fake-visor/no-transfer case, but that practical exploit is already captured by F-002. No evidence in this codebase supports a separate realistic short-transfer path for the fixed VISR token, so keeping it standalone would be duplicative and overly speculative. |
