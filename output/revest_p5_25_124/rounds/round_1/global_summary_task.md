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
- files touched: `onchain_auto/0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/Revest.sol`, `onchain_auto/0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/FNFTHandler.sol`, scoped interfaces/OpenZeppelin files via directory listing
- files revisited / highest-attention files: `Revest.sol` was revisited multiple times around minting, split, deposit, and fee paths; `FNFTHandler.sol` was revisited for id allocation / mint behavior
- main issue directions investigated: FNFT id allocation and reentrancy around mint hooks/callbacks; WETH mint funding flow and fee handling; fee-on-transfer collateral accounting; `depositAdditionalToFNFT()` deadline logic; address-lock trigger validation
- promising but not retained directions: broad source-root mapping / compile-context checks were attempted, but no additional retained issue beyond the five reported findings is visible in the log

## Agent: opencode_1
- files touched: `onchain_auto/0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/Revest.sol`, `onchain_auto/0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/FNFTHandler.sol`, `onchain_auto/0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/utils/RevestAccessControl.sol`, `onchain_auto/0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/IRevest.sol`, `onchain_auto/0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/ITokenVault.sol`, `onchain_auto/0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/ILockManager.sol`, `onchain_auto/0x2320a28f52334d62622cc2eafa15de55f9987ed9/contracts/interfaces/IAddressLock.sol`
- files revisited / highest-attention files: `Revest.sol` and `FNFTHandler.sol` were the clear focus
- main issue directions investigated: fee-on-transfer collateral mismatch; FNFT id / counter behavior; address-lock behavior; split/deposit flows; oracle/value-lock assumptions; access-control and maturity-extension checks
- promising but not retained directions: integer-overflow fee math, burn underflow/desync, oracle price manipulation, split proportionality concerns, maturity-extension access control, unchecked external-call return, approval-risk / stale allowance, zero-asset validation, non-transferable FNFT griefing

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `Revest.sol` and `FNFTHandler.sol`, especially mint/deposit/split mechanics and collateral accounting
- notable differences in attention: `codex_1` stayed narrowly on concrete mint/deposit path bugs and produced the retained findings; `opencode_1` scanned a wider set of speculative themes including oracle design, access control, approvals, and arithmetic
- underexplored but suspicious files/functions if clearly supported by the logs: value-lock/oracle-related paths in `Revest.sol` and `IRevest.sol` were at least flagged by `opencode_1`, but no retained finding from this round confirms them

## Retained Findings
- retained issues from this round center on `Revest.sol` / `FNFTHandler.sol` mint and deposit mechanics: reentrant FNFT id reuse, stranded ETH during WETH-backed mints, fee-on-transfer undercollateralization, reversed additional-deposit deadline logic, and non-compliant address-lock triggers causing lock-risk


Output only markdown.
