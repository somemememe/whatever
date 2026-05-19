# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 5

## Finding Actions
- rewritten_agent_signal: 4

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | Fake or short-paying `IVisor` deposits can mint unbacked shares and drain pooled VISR | codex_1:0.704 Arbitrary fake `IVisor` contracts can mint unbacked shares and drain the pool |
| F-002 | rewritten_agent_signal | Critical | high | codex_1,opencode_1 | The first depositor can seize any VISR that reaches the Hypervisor before shares exist | codex_1:0.753 The first depositor can seize any VISR pre-seeded before share supply starts |
| F-003 | rewritten_agent_signal | High | high | codex_1,opencode_1 | Direct VISR donations let existing shareholders force zero or underpriced mints and capture later deposits | codex_1:0.393 Arbitrary fake `IVisor` contracts can mint unbacked shares and drain the pool |
| F-004 | rewritten_agent_signal | Critical | high | merge_review | Anyone can steal approved VISR by depositing from another user's address and minting shares to themselves | codex_1:0.387 Deposits are priced from the requested amount instead of the actual VISR received |

## Rejection Reasons
- other: 2
- trust_or_owner_model: 2
- unsupported_or_speculative: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| trust_or_owner_model | opencode_1 | Unprotected Mint and Burn Functions in vVISR | Rejected: `vVISR` defines its own `owner` storage, initializes it in the constructor, and gates `mint()`/`burn()` with a functioning custom `onlyOwner` modifier. |
| other | opencode_1 | Share Calculation Uses Post-Transfer Balance Without Verification | Rejected: the share calculation happens before either transfer branch executes, not after; the real reportable issue is the unverified contract-path transfer, which is already covered by F-001. |
| trust_or_owner_model | opencode_1 | Missing Validation for Share Burning in Withdraw | Rejected: `withdraw()` requires `from == msg.sender` or `IVisor(from).owner() == msg.sender`, and `vVISR.burn()` is intentionally callable only by the token owner contract. |
| other | opencode_1 | Inconsistent Compiler Version and Missing License | Rejected: outdated compiler choice and license metadata are not protocol-level vulnerabilities in this codebase. |
| unsupported_or_speculative | codex_1 | Deposits are priced from the requested amount instead of the actual VISR received | Not kept as a separate finding: the concrete exploitably supported portion is the contract-path under-transfer/no-transfer bug, which is merged into F-001; broader fee-on-transfer or rebasing assumptions about the configured VISR token are too speculative here. |
