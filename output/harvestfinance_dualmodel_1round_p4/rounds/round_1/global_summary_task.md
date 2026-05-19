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

## Agent: codex_1
- files touched: `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultStorage.sol`, `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV1.sol`, `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV2.sol`, `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/inheritance/Storage.sol`, `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/inheritance/GovernableInit.sol`, `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/inheritance/ControllableInit.sol`, `0xf0358e8c3cd5fa238a29301d0bea3d63a17bedbe/Contract.sol`, plus a broad scan of in-scope `.sol` files
- files revisited / highest-attention files: `VaultV1.sol`, `VaultV2.sol`, `VaultStorage.sol`; later line-anchor review also revisited `Contract.sol`
- main issue directions investigated: proxy/initializer takeover risk, zero-supply vault share-accounting edge cases, ERC4626 `mint`/`withdraw` rounding and compliance behavior, empty-vault view-helper behavior, strategy-reported NAV trust in pricing
- promising but not retained directions: strategy NAV manipulation / mispricing based on `investedUnderlyingBalance()` was explored and emitted in the draft output, but it was not retained after merge

## Agent: opencode_1
- files touched: `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV1.sol`, `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultV2.sol`, `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/VaultStorage.sol`, `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/inheritance/ControllableInit.sol`, `0x0de5f3a958f8e927c5b27d202d12b607e213d08c/contracts/base/inheritance/GovernableInit.sol`
- files revisited / highest-attention files: visible attention was concentrated on `VaultV1.sol`, `VaultV2.sol`, and related initialization/storage helpers
- main issue directions investigated: main vault contracts and related inheritance / initialization files
- promising but not retained directions: `contracts/base/inheritance/Storage.sol` appears to have been the next intended target in the final output, but no completed investigation or finding is visible in the logs

## Cross-Agent Status
- main overlap in file/area attention: both agents focused on `VaultV1.sol`, `VaultV2.sol`, `VaultStorage.sol`, and the initialization/governance helper inheritance contracts
- notable differences in attention: `codex_1` extended into proxy deployment code in `0xf0358e8c3cd5fa238a29301d0bea3d63a17bedbe/Contract.sol` and produced concrete issue hypotheses; `opencode_1` log shows only early-stage reading with no completed findings
- underexplored but suspicious files/functions if clearly supported by the logs: `contracts/base/inheritance/Storage.sol` had visible but incomplete follow-up attention; proxy logic in `Contract.sol` received attention from only one agent

## Retained Findings
- retained issues from this round are all from `codex_1`: uninitialized vault proxy takeover, zero-supply vault first-depositor asset capture, ERC4626 `mint()` under-mint / zero-share charging, ERC4626 `withdraw()` short-pay behavior, and empty-vault ERC4626 helper reverts


Output only markdown.
