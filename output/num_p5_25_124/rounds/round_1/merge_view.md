# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 6

## Finding Actions
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-002 | rewritten_agent_signal | High | high | codex_1 | Permit-based bridge entrypoints let arbitrary callers redirect a signer’s funds to attacker-chosen recipients, chains, and routes | codex_1:0.822 Permit-based bridge entrypoints let any caller redirect a signer’s funds to arbitrary recipients and chains |
| F-003 | rewritten_agent_signal | High | medium | codex_1,opencode_1 | Cross-chain trade entrypoints burn source funds immediately but provide no on-chain recovery path if destination execution reverts | codex_1:0.656 Cross-chain trade entrypoints burn source funds before proving destination execution is possible and provide no refund path |
| F-004 | rewritten_agent_signal | Medium | high | codex_1 | User trade deadlines are enforced only on the source chain and can be bypassed on destination execution | codex_1:0.618 User trade deadlines are not preserved across chains, so destination execution can occur after expiry |

## Rejection Reasons
- other: 5
- trust_or_owner_model: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | codex_1 | Inbound bridge executions are replayable because processed tx hashes are never recorded | `txs` is only emitted metadata; the trusted `onlyMPC` role can already call `anySwapIn*` with arbitrary parameters, so lack of on-chain replay tracking does not create a distinct, non-privileged exploit path. |
| other | opencode_1 | MPC 2-day delay bypassed on initial deployment | The constructor needs an immediately active MPC so the router is operable after deployment; the 2-day delay applies to later MPC changes, not initial bootstrap. |
| other | opencode_1 | Slippage protection parameter accepted but not enforced | `amountOutMin` is enforced on the destination-side `anySwapInExactTokensForTokens` and `anySwapInExactTokensForNative` calls. The real issue is missing on-chain commitment/recovery for cross-chain execution, which is captured separately. |
| other | opencode_1 | Batch function arrays not validated for equal length | Mismatched array lengths only cause the caller’s own transaction to revert via bounds checks; this is not a realistic protocol-level loss, theft, insolvency, or permissionless DoS issue. |
| other | opencode_1 | Initial _oldMPC is address(0) causing undefined behavior during transitions | On the first `changeMPC`, `_oldMPC` is assigned `mpc()`, which returns the currently active `_newMPC`, not zero. The claimed zero-address transition window does not occur. |
| other | opencode_1 | Plain anySwapOut lacks minimum amount parameter | `anySwapOut` is a simple bridge burn/mint flow, not a swap execution path with price discovery, so an `amountOutMin` parameter is not relevant there. |
