# Merge View - Round 1

## Summary
- total findings: 3
- new findings: 3
- updated existing findings: 0
- rejected candidates: 10

## Finding Actions
- exact_agent_candidate: 2
- rewritten_agent_signal: 1

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | exact_agent_candidate | Critical | medium | codex_1 | Beacon proxies can be left uninitialized and then fully hijacked | codex_1:1.0 Beacon proxies can be left uninitialized and then fully hijacked |
| F-002 | exact_agent_candidate | High | medium | codex_1 | Updater signatures are replayable across deployments that reuse the same domain and updater key | codex_1:1.0 Updater signatures are replayable across deployments that reuse the same domain and updater key |
| F-003 | rewritten_agent_signal | Medium | medium | codex_1 | Replica silently truncates 32-byte recipients to 20 bytes and dispatches to non-contract addresses | codex_1:0.75 Replica truncates 32-byte recipients to 20 bytes and dispatches without validating code exists |

## Rejection Reasons
- other: 7
- trust_or_owner_model: 3

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex_1 | The documented `Failed` state does not actually stop updates or message execution | The `state` variable is indeed unused, but this codebase exposes no reachable path that ever sets `state = Failed`; in the current implementation it is dead code/comment drift rather than an exploitable protocol flaw. |
| other | codex_1 | Updater rotation can permanently orphan already-signed but unrelayed roots | Changing `updater` invalidates old signatures, but the new updater can re-sign the same root transition or any later append-only root, so the code does not itself permanently strand messages. |
| other | opencode_1 | Missing Origin Domain Verification Allows Arbitrary Cross-Domain Message Injection | The message `origin` field is authenticated by Merkle inclusion in an updater-signed root for the followed Home; lack of a separate `origin == remoteDomain` check is not a standalone forgery vector. |
| other | opencode_1 | prove() Allows Re-proving Messages Under New Roots Without Validation | Re-proving an unprocessed message under another acceptable root is intentional append-only behavior and does not bypass the processed check or create capabilities beyond whatever roots are already trusted. |
| trust_or_owner_model | opencode_1 | Governance Can Set Arbitrary Roots Bypassing Security Controls | `setConfirmation` is an explicit owner-only emergency override; a malicious or compromised governance owner is a trust assumption, not a distinct implementation bug. |
| trust_or_owner_model | opencode_1 | Single Updater Key Creates Centralized Single Point of Failure | This is a protocol trust-model observation rather than a code vulnerability; the contracts are explicitly designed around a trusted updater role. |
| other | opencode_1 | Optimistic Timeout Can Be Set To Zero During Initialization | The lack of a minimum on first initialization is an explicit deployment/configuration choice for testing/bootstrap scenarios and requires trusted deployment misconfiguration, not a permissionless exploit. |
| other | opencode_1 | No Protection Against Proof Reuse After Message Processing | Processed messages cannot be reproven because `prove()` rejects `LEGACY_STATUS_PROCESSED`; reproving before processing is the same intended behavior already covered by the other re-proving candidate and is not independently exploitable. |
| other | opencode_1 | process() Does Not Check Return Value of handle() External Call | `IMessageRecipient.handle` has no return value; if the external call reverts, the whole transaction reverts and the processed status/event are rolled back, so there is no false-success path from an ignored return value. |
| trust_or_owner_model | opencode_1 | Missing Zero Address Check for Updater | Setting `updater` to `address(0)` is recoverable by the owner via a later `setUpdater` call, so it does not permanently brick the bridge and is not a protocol-level vulnerability. |
