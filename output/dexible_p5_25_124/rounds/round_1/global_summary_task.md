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
- files touched: `Dexible.sol`, `SwapHandler.sol`, `ConfigBase.sol`, `AdminBase.sol`, `DexibleProxy.sol`, `IRewardHandler.sol`, `ICommunityVault.sol`, `V1Migrateable.sol`
- files revisited / highest-attention files: `SwapHandler.sol`, `Dexible.sol`, `ConfigBase.sol`, `DexibleProxy.sol`
- main issue directions investigated: permissionless swap execution and relay-boundary bypass; unrestricted `router.call(...)` behavior from Dexible; proxy initialization / admin takeover conditions
- promising but not retained directions: nested `selfSwap()` -> `fill()` relay bypass as a narrower framing of the retained arbitrary-call theft issue; route access to Dexible-privileged vault hooks such as `rewardTrader()`; later-route draining of Dexible-held residual ERC20 balances

## Agent: opencode_1
- files touched: `Dexible.sol`, `SwapHandler.sol`, `DexibleStorage.sol`, `ConfigBase.sol`, `AdminBase.sol`, `VaultStorage.sol`, `IDXBL.sol`, `LibFees.sol`, `DexibleProxy.sol`, `DexibleView.sol`, `SwapTypes.sol`, `TokenTypes.sol`, `ExecutionTypes.sol`, `ICommunityVault.sol`, `IDexible.sol`, `IDexibleConfig.sol`, `IStandardGasAdjustments.sol`
- files revisited / highest-attention files: `Dexible.sol`, `SwapHandler.sol`, `ConfigBase.sol`, `DexibleProxy.sol`, `VaultStorage.sol`
- main issue directions investigated: initialization / admin-control weaknesses; swap-path external call risk; fee and payout handling; broader config and gas-accounting safety
- promising but not retained directions: reentrancy around swap/fee distribution; arbitrary router approval / execution concerns in broader form; affiliate fee redirection; zero-address config hazards; gas-fee/oracle issues; ETH transfer method reliability; direct implementation initialization concerns

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `Dexible.sol`, `SwapHandler.sol`, `ConfigBase.sol`, and `DexibleProxy.sol`, converging on swap execution authority and initialization/admin control
- notable differences in attention: `codex_1` pushed deeper into vault-trust and route-execution edge cases, while `opencode_1` spread attention across fee logic, storage/types, and broader configuration surfaces
- underexplored but suspicious files/functions if clearly supported by the logs: vault reward/redemption trust boundaries remain only lightly explored relative to core swap/proxy paths; `LibFees.sol` and view/type modules were touched mainly by `opencode_1` without retained outcomes

## Retained Findings
- Public swap entry plus unrestricted route execution was retained as the core theft primitive: Dexible can be used as a permissionless arbitrary-call proxy to move approved user funds or Dexible-held ERC20 balances.
- Optional or failed proxy initialization was retained as the main control-plane risk: an uninitialized live proxy can be seized by the first external initializer, granting admin and upgrade control.


Output only markdown.
