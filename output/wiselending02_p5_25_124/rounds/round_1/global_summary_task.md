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
- files touched: `WiseLending.sol`, `WiseCore.sol`, `MainHelper.sol`, `WiseLowLevelHelper.sol`, `PoolManager.sol`, `TransferHub/CallOptionalReturn.sol`, `TransferHub/TransferHelper.sol`, `InterfaceHub/IWiseSecurity.sol`
- files revisited / highest-attention files: `WiseLending.sol`, `WiseCore.sol`, `MainHelper.sol`
- main issue directions investigated: WETH deposit/mint synchronization, inbound ERC20 accounting vs actual received amount, ignored ERC20 `false` return values, liquidation share-allocation bookkeeping, position token-list cleanup limits, isolation-pool lock registration
- promising but not retained directions: none clearly visible beyond the retained findings set

## Agent: opencode_1
- files touched: `WiseLending.sol`, `WiseCore.sol`, `MainHelper.sol`, `WiseLendingDeclaration.sol`, `InterfaceHub/IWiseSecurity.sol`, `PoolManager.sol`, `WiseLowLevelHelper.sol`, `OwnableMaster.sol`, `TransferHub/TransferHelper.sol`, `TransferHub/CallOptionalReturn.sol`, `InterfaceHub/IWiseOracleHub.sol`, `Babylonian.sol`
- files revisited / highest-attention files: `WiseLending.sol`, `WiseCore.sol`, `MainHelper.sol`, `WiseLendingDeclaration.sol`
- main issue directions investigated: liquidation/payback flows, ERC20 transfer handling, oracle/security assumptions, privileged master controls, pool-parameter setup, bypass paths for integrations
- promising but not retained directions: `skim()`/master excess-token control, missing pause/emergency stop, approval/front-running concerns, broad oracle manipulation themes, AaveHub/isolation-pool bypass concerns, `setSecurity` zero-address handling, timelock/governance-risk items

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `WiseLending.sol` and `WiseCore.sol`, especially deposit/payback/liquidation accounting and ERC20 transfer handling
- notable differences in attention: `codex_1` focused on concrete accounting/bookkeeping bugs and WETH sync behavior; `opencode_1` spent more attention on governance, oracle, and privileged-control themes in `WiseLendingDeclaration.sol`, `PoolManager.sol`, and `OwnableMaster.sol`
- underexplored but suspicious files/functions if clearly supported by the logs: `WiseLowLevelHelper.sol`, `PoolManager.sol`, and `WiseLendingDeclaration.sol` were read by both/one agent but produced little or no retained output relative to their protocol-control surface

## Retained Findings
- Retained issues centered on core asset accounting and state consistency in lending flows.
- High-severity findings covered stale-price WETH mint deposits, ERC20 inbound accounting that trusts requested amounts, and transfer helpers that ignore `false` returns.
- Additional retained issues covered liquidation bookkeeping misassignment, large-position token cleanup overflow/DoS risk, and overly broad isolation-pool lock toggling.


Output only markdown.
