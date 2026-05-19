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
- files touched: `0x863e572b215fd67c855d973f870266cf827aea5e/contracts/core/Vault.sol`; Solidity file inventory via `rg`; `0x863e572b215fd67c855d973f870266cf827aea5e/@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol`
- files revisited / highest-attention files: `contracts/core/Vault.sol` was the clear focus
- main issue directions investigated: vault share/accounting math in `deposit()` and `withdraw()`, especially zero-burn withdrawals, zero-share deposits, post-transfer share pricing, and unrestricted `subStrategy`-driven minting
- promising but not retained directions: stronger controller-dependent theories were considered, but the agent explicitly narrowed retained claims to bugs provable from vault-side logic without assuming specific `controller` behavior

## Agent: opencode_1
- files touched: `0x863e572b215fd67c855d973f870266cf827aea5e/contracts/core/Vault.sol`; `0x863e572b215fd67c855d973f870266cf827aea5e/contracts/interfaces/IController.sol`; `0x863e572b215fd67c855d973f870266cf827aea5e/contracts/interfaces/IVault.sol`; `0x863e572b215fd67c855d973f870266cf827aea5e/contracts/utils/TransferHelper.sol`
- files revisited / highest-attention files: `contracts/core/Vault.sol` dominated attention, with interface/transfer helper reads used for context
- main issue directions investigated: ETH-vs-ERC20 deposit behavior, controller trust/validation, withdraw return-value handling, share-conversion division-by-zero cases, lack of slippage-style protection, and `subStrategy`/admin configuration surfaces
- promising but not retained directions: several ideas centered on owner-configurable controller risk, generic zero-address/interface validation, view-function reverts, and debug logging remained unretained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `contracts/core/Vault.sol`, especially deposit/withdraw accounting and privileged control points around controller/sub-strategy wiring
- notable differences in attention: `codex_1` focused on exploitable vault math and retained share-accounting bugs; `opencode_1` spent more attention on architectural/configuration concerns and interface/asset-model inconsistencies
- underexplored but suspicious files/functions if clearly supported by the logs: `IController` interactions remain a notable dependency surface, but round-1 retained claims were intentionally limited where controller semantics were not provable from the visible code

## Retained Findings
- Retained issues were all centered on `Vault.sol`: zero-share-burn withdrawals, unrestricted sub-strategy share minting, post-transfer deposit pricing that can under-mint users, zero-share deposit acceptance, and silent acceptance of excess ETH sent to `deposit()`
- After merge, the round kept four findings sourced from `codex_1` and one additional low-severity excess-ETH finding sourced from `merge_review`


Output only markdown.
