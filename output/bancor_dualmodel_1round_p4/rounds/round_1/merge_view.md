# Merge View - Round 1

## Summary
- total findings: 5
- new findings: 5
- updated existing findings: 0
- rejected candidates: 6

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | high | codex_1 | Inherited public token helper functions let any caller move funds as BancorNetwork | codex_1:0.935 Public token helper functions let any caller move funds as BancorNetwork |
| F-002 | exact_agent_candidate | High | high | codex_1 | ETH-consuming conversion steps forward stale `msg.value` instead of the hop amount | codex_1:0.852 ETH-paying conversion steps forward the original `msg.value` instead of the step amount |
| F-003 | rewritten_agent_signal | Medium | low | codex_1 | User-supplied path anchors can redirect source tokens to arbitrary contracts | codex_1:0.426 Unvalidated path anchors let a malicious frontend turn the official router into a token drain |
| F-004 | rewritten_agent_signal | Medium | medium | codex_1 | ETH/EtherToken normalization is only applied at path endpoints, breaking internal ETH hops | codex_1:0.795 ETH/EtherToken normalization is only applied at the path endpoints |
| F-005 | rewritten_agent_signal | High | medium | opencode_1,merge_reviewer | `completeXConversion` never sources the bridged tokens from BancorX | opencode_1:0.504 completeXConversion allows stealing funds from cross-chain transfers |

## Rejection Reasons
- other: 6

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | opencode_1 | completeXConversion allows stealing funds from cross-chain transfers | The BancorNetwork code queries `_bancorX.getXTransferAmount(_conversionId, msg.sender)`, so this contract does not itself authorize a caller to claim someone else's transfer. The supported issue here is a broken funding flow, not a demonstrated front-runnable theft path. |
| other | opencode_1 | updateRegistry allows unauthorized registry modification | `updateRegistry()` does not let callers choose an arbitrary registry; it only follows the current registry's `CONTRACT_REGISTRY` pointer. Permissionless update appears to be an intended sync mechanism, not a direct attacker-controlled hijack from this code alone. |
| other | opencode_1 | No validation that affiliate account can receive tokens | The affiliate fee is paid with an ERC20 transfer, which does not require a payable fallback or token-receiver hook. A bad affiliate address would at most cause the caller's own transaction to revert; it is not a protocol-level vulnerability. |
| other | opencode_1 | Approve race condition in ensureAllowance | The allowance being changed belongs to BancorNetwork itself and is granted only to the designated converter or BancorX contract. The generic ERC20 approve race does not create an independent attacker path here without already assuming a malicious spender. |
| other | opencode_1 | Missing zero-address check for affiliate account | `convertByPath` already treats `address(0)` as affiliate-fee disabled and explicitly requires `_affiliateFee == 0` in that case, so affiliate fees cannot be burned to the zero address through this path. |
| other | opencode_1 | Deprecated functions lack input validation | The deprecated wrappers all route into `convertByPath`, which itself enforces `greaterThanZero(_minReturn)`, so `_minReturn == 0` is still rejected. |
