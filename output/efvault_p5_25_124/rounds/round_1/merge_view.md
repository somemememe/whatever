# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Anyone can mint vault shares using assets already sitting in the vault | codex_1:1.0 Anyone can mint vault shares using assets already sitting in the vault |
| F-002 | exact_agent_candidate | High | high | codex_1 | Rounding down in `withdraw` lets users withdraw assets while burning zero shares | codex_1:1.0 Rounding down in `withdraw` lets users withdraw assets while burning zero shares |
| F-003 | exact_agent_candidate | Medium | high | codex_1 | Small deposits can transfer assets into the strategy while minting zero shares | codex_1:0.963 Small deposits can transfer assets into the vault strategy while minting zero shares |
| F-004 | exact_agent_candidate | Low | high | codex_1 | Whitelist enforcement is bypassed for every direct EOA caller | codex_1:1.0 Whitelist enforcement is bypassed for every direct EOA caller |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | Child UUPS implementation has no upgrade authorization, enabling arbitrary implementation takeover | The code is confined to `contracts/test/Proxiable.sol`, is not referenced by any non-test contract in this snapshot, and there is no evidence it is part of a live protocol deployment. As provided, it is a vulnerable test helper rather than a reportable protocol issue. |
