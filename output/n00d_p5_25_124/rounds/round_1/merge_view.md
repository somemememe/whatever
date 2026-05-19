# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 5

## Finding Actions
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | low | codex_1,opencode_1 | Deployment can embed global operators with authority to move or burn every holder's tokens | codex_1:0.61 Deployment-time default operators can drain or burn every holder's balance |
| F-002 | rewritten_agent_signal | High | high | codex_1 | ERC20-looking transfers still execute ERC777 recipient hooks, enabling callback reentrancy in integrators | codex_1:0.847 ERC20-looking transfers still execute recipient callbacks, enabling reentrancy against integrators |
| F-003 | rewritten_agent_signal | Medium | medium | codex_1 | Sender-side ERC777 hooks run before balances are debited, exposing pull and burn flows to pre-state reentrancy | codex_1:0.687 Sender-side ERC777 hook fires before debiting balances, enabling pre-state reentrancy |

## Rejection Reasons
- low_impact_or_operational: 1
- other: 4

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | ERC20 entrypoints bypass recipient acknowledgment and can permanently lock tokens in contracts | This is intentional ERC20-compatibility behavior inherited from OpenZeppelin ERC777: `transfer`/`transferFrom` are allowed to send into non-ERC777 contracts just like normal ERC20s. Any lockup depends on the recipient contract lacking an exit path, which is an integration/user mistake rather than a token-specific flaw. |
| other | codex_1 | Allowance changes are vulnerable to the standard ERC20 approval race | This is the well-known ERC20 allowance race from overwrite-style `approve`, with standard zero-reset mitigation. It is not a custom bug in this implementation and is generally treated as non-reportable absent unusual token-specific behavior. |
| other | codex_1 | Hard-coded ERC1820 registry dependency can brick the token on networks without the registry | This is a generic ERC777 deployment prerequisite and portability concern, not a vulnerability in the deployed token instance absent evidence it is intended for a network without the canonical ERC1820 registry. |
| other | opencode_1 | Unlimited Token Minting Through Inheritance | `_mint` is `internal`, but inheriting from this source code and deploying a child contract would create a different token contract, not mint more balances into the already-deployed `n00d` at `0x2321537fd8ef4644bacdceec54e5f35bf44311fa`. |
| low_impact_or_operational | opencode_1 | ERC777 Hooks Can Cause Permanent Transfer Locks | A sender or recipient hook can only block transfers involving the account that voluntarily registered that hook. That is opt-in/self-griefing behavior defined by ERC777, not a realistic protocol-level vulnerability in this token. |
