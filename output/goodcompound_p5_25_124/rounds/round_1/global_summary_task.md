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
- files touched: `0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b/Contract.sol`, `0xbafe01ff935c7305907c33bf824352ee5979b526/contracts/CToken.sol`, `Comptroller.sol`, `ComptrollerStorage.sol`, and related interfaces via broad grep/money-flow mapping
- files revisited / highest-attention files: `Contract.sol` and `Comptroller.sol`
- main issue directions investigated: legacy flattened CToken accounting around `mint` / `repayBorrow` / `liquidateBorrow`; `accountAssets` growth and liquidity-loop gas griefing in `Comptroller`; COMP accrual remediation around `fixBadAccruals`
- promising but not retained directions: cross-market stale-state reentrancy via `doTransferOut` / global liquidity checks was proposed but not retained after merge

## Agent: opencode_1
- files touched: `0xbafe01ff935c7305907c33bf824352ee5979b526/contracts/CToken.sol`, `Comptroller.sol`, `Unitroller.sol`, `CTokenInterfaces.sol`, `ComptrollerStorage.sol`, `Exponential.sol`, `0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b/Contract.sol`
- files revisited / highest-attention files: `CToken.sol` and `Comptroller.sol`
- main issue directions investigated: privileged parameter changes and missing validation; oracle / comptroller / interest-rate-model replacement risk; guardian pause and borrow-cap controls; market deprecation liquidation behavior; `fixBadAccruals`; `Unitroller` delegatecall upgrade surface
- promising but not retained directions: admin-centralization and timelockless-control findings, `Unitroller` delegatecall risk, and deprecation-based liquidation abuse were proposed in output but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `Comptroller.sol` plus core CToken borrow/redeem/liquidation flows
- notable differences in attention: `codex_1` focused on concrete accounting failures in the legacy flattened `Contract.sol`; `opencode_1` focused mainly on privileged control, upgradeability, and governance surfaces in `Comptroller` / `Unitroller` / `CToken`
- underexplored but suspicious files/functions if clearly supported by the logs: `Unitroller.sol` upgrade/fallback path received only one-agent attention and no retained issue; the canonical `CToken.sol` transfer-out / reentrancy path was investigated but not retained

## Retained Findings
- Retained issues center on two areas: legacy flattened `Contract.sol` has three fee-on-transfer accounting failures that over-credit minting, repayment, and liquidation; `Comptroller` has an unenforced `maxAssets` cap enabling asset-list gas griefing and a `fixBadAccruals` remediation path that records COMP receivables without affecting later claims.


Output only markdown.
