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
- files touched: mapped both `onchain_auto/0x3d5.../contracts` and `onchain_auto/0x7aa.../contracts`; detailed reads centered on `onchain_auto/0x7aa375f1fe5e04e18a6b02b4294cfd57ca9f53ba/contracts/CToken.sol`, `onchain_auto/0x7aa375f1fe5e04e18a6b02b4294cfd57ca9f53ba/contracts/Comptroller.sol`, and `onchain_auto/0x7aa375f1fe5e04e18a6b02b4294cfd57ca9f53ba/contracts/ComptrollerStorage.sol`
- files revisited / highest-attention files: highest attention was on `Comptroller.sol`; revisited targeted regions around redeem/repay policy hooks, market entry, and liquidity calculation loops
- main issue directions investigated: redeem/transfer authorization flow, repay/liquidation authorization flow, `maxAssets` / `accountAssets` enforcement versus liquidity-loop usage, and collateral-cap membership hook ordering
- promising but not retained directions: broader scans of flash-loan, mint/borrow/seize/admin paths and the parallel `0x3d5...` branch were explored but did not produce retained findings in this round

## Agent: opencode_1
- files touched: `onchain_auto/0x7aa375f1fe5e04e18a6b02b4294cfd57ca9f53ba/contracts/CToken.sol`, `onchain_auto/0x7aa375f1fe5e04e18a6b02b4294cfd57ca9f53ba/contracts/Comptroller.sol`, `onchain_auto/0x7aa375f1fe5e04e18a6b02b4294cfd57ca9f53ba/contracts/CTokenInterfaces.sol`, `onchain_auto/0x7aa375f1fe5e04e18a6b02b4294cfd57ca9f53ba/contracts/Unitroller.sol`, `onchain_auto/0x7aa375f1fe5e04e18a6b02b4294cfd57ca9f53ba/contracts/ComptrollerStorage.sol`, plus `onchain_auto/0x3d5bc3c8d13dcb8bf317092d84783c2697ae9258/contracts/CToken.sol`
- files revisited / highest-attention files: `Comptroller.sol` received the most attention, including a later offset read and targeted greps for `revert(` and flash-loan references
- main issue directions investigated: unconditional reverts in redeem and repay policy hooks, flash-loan-related logic, proxy/storage context via `Unitroller.sol` and `ComptrollerStorage.sol`, and a possible redundant revert in `redeemVerify`
- promising but not retained directions: the `redeemVerify` redundancy idea was reported but not retained after merge; flash-loan and proxy/upgradability areas were inspected without a retained issue from this round

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `onchain_auto/0x7aa.../contracts/Comptroller.sol` and `CToken.sol`, especially redeem and repay control-flow hooks
- notable differences in attention: `codex_1` pushed further into `accountAssets`/liquidity-loop behavior and collateral-cap hook ordering, while `opencode_1` spent more visible effort on flash-loan greps, `Unitroller.sol`, and a `redeemVerify` edge case
- underexplored but suspicious files/functions if clearly supported by the logs: flash-loan paths in `onchain_auto/0x7aa.../contracts/CToken.sol` and upgrade/proxy surfaces in `onchain_auto/0x7aa.../contracts/Unitroller.sol` were touched but did not yet yield retained findings; the `0x3d5...` branch saw comparatively lighter visible follow-through

## Retained Findings
- merged retention kept two protocol-breaking policy-hook reverts in `Comptroller.sol`: one bricks redemption / exit / cToken transfer paths, and one bricks repayment and liquidation repayment paths
- retained one gas-DoS style issue where `accountAssets` is no longer capped in practice, making liquidity and liquidation checks scale with an unbounded entered-market set
- retained one low-confidence collateral-cap accounting issue where collateral registration occurs before membership checks, making repeated market entry depend on cToken hook idempotence


Output only markdown.
