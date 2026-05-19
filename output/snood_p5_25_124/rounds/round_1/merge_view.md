# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 7

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Bridge owner can mint arbitrary unbacked tokens without consuming any burn record | codex_1:0.813 Bridge owner can mint arbitrary unbacked tokens with no proof of burn |
| F-002 | exact_agent_candidate | High | high | codex_1 | Ownership transfer or renounce leaves the previous owner with live `DEFAULT_ADMIN_ROLE` powers | codex_1:0.932 Ownership transfer leaves the previous owner with live `DEFAULT_ADMIN_ROLE` powers |
| F-003 | exact_agent_candidate | High | high | codex_1,opencode_1 | Transfers and burns depend on a mutable external farming contract and can be globally frozen | codex_1:0.952 Every transfer and burn depends on a mutable external farming contract and can be globally frozen |
| F-004 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Hardcoded maintenance routine confiscates balances from listed holder addresses | codex_1:0.748 Hardcoded maintenance function is a confiscation backdoor for listed holders |
| F-005 | rewritten_agent_signal | Medium | medium | merge_review | `configure(true, ...)` is repeatable and leaves stale farming contracts permanently privileged while stranding the old farming reserve | codex_1:0.39 Every transfer and burn depends on a mutable external farming contract and can be globally frozen |

## Rejection Reasons
- low_impact_or_operational: 1
- other: 5
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | Inverted logic in transfer validation allows any transfer | The `require` predicate is wrong, but ERC777 still enforces `fromBalance >= amount` in `_move` and `_burn`, so over-balance transfers and burns revert rather than enabling theft. |
| other | opencode_1 | Predictable farming fund address allows front-running | The `_farmingFund` address being derivable from block data does not by itself give an attacker control over that address or a practical way to steal protocol funds. |
| other | codex_1 | UUPS test implementation has no upgrade authorization and is fully takeoverable | The issue is confined to `contracts/test/Proxiable.sol`; without evidence that this test helper is part of a deployed production path, it is not a reportable protocol finding. |
| other | opencode_1 | Fee calculation loses precision due to integer division order | This is standard integer-rounding behavior in fee math and no realistic protocol-level loss, theft, or lockup path was substantiated. |
| other | opencode_1 | Token burn occurs before state update | If anything later reverted, the entire transaction would revert atomically and undo the burn; the cited mapping increment does not create an independent loss scenario. |
| low_impact_or_operational | opencode_1 | External call without reentrancy guard | `payFee` uses `transfer`, which forwards minimal gas, and there is no vulnerable post-call state to exploit; this is not a realistic reentrancy issue here. |
| trust_or_owner_model | opencode_1 | Lack of access control on farming configuration | The cited configuration is explicitly protected by `onlyOwner`, so this is expected governance authority rather than unintended privilege escalation. |
