You maintain a concise global audit memory for future audit agents.

Update the existing global memory by folding in durable observations from the
latest round summary. The goal is an accumulated cross-round audit view, not a
per-round recap.

This memory is optional context only. Findings are stored separately.

Write the updated memory in this exact structure:

# Global Audit Memory

## Scope Touched
- files/contracts/flows that have mattered across rounds, with short issue-direction notes

## Issue Directions Seen
- recurring or promising vulnerability directions seen across the audit

## Useful Context
- compact cross-round observations 

Rules:
- keep it compact
- preserve useful prior context while integrating new durable observations
- prefer stable cross-round patterns over latest-round details
- fold repeated wording into a single clearer observation
- keep the memory descriptive rather than prescriptive

## Existing Global Memory
No global memory yet.

## Latest Round Summary
# Round 1 Summary

## Agent: codex
- files touched: `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/contracts/RubicProxy.sol`, `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/BridgeBase.sol`, `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/architecture/OnlySourceFunctionality.sol`, `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/libraries/SmartApprove.sol`, `onchain_auto/0x3335a88bb18fd3b6824b59af62b50ce494143333/rubic-bridge-base/contracts/errors/Errors.sol`, `src/FlawVerifier.sol`
- files revisited / highest-attention files: `contracts/RubicProxy.sol`, `rubic-bridge-base/contracts/BridgeBase.sol`, `rubic-bridge-base/contracts/libraries/SmartApprove.sol`
- main issue directions investigated: shared router/gateway allowlist behavior, persistent approval lifecycle, token amount accounting for fee-on-transfer assets, native-call refund handling, unenforced per-token min/max controls
- promising but not retained directions: the split between router allowlisting and spender approval authority was initially reported separately, but after merge the retained issue centers on the combined shared-allowlist plus sticky-approval drain path

## Cross-Agent Status
- main overlap in file/area attention: single-agent round; attention concentrated on `RubicProxy.sol` and its bridge-base dependencies
- notable differences in attention: no cross-agent differences in this round
- underexplored but suspicious files/functions if clearly supported by the logs: `src/FlawVerifier.sol` was searched for interface/parameter tracing but did not appear to receive the same depth of review as the proxy and bridge-base contracts

## Retained Findings
- retained high-severity issue on shared router/gateway allowlisting combined with non-revoked max approvals enabling allowlisted spenders to drain proxy-held tokens
- retained high-severity issue on fee-on-transfer / deflationary token handling where routes can be subsidized from pre-existing proxy balances
- retained medium-severity issue on native route refunds or unspent ETH becoming trapped in the proxy and later admin-sweepable
- retained low-severity issue that configured per-token min/max amount limits exist in storage/admin setters but are not enforced by route entrypoints


Output only markdown.
