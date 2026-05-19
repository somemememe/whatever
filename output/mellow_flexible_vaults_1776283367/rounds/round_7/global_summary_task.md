You maintain a concise global audit memory for future audit agents.

Update the existing global memory using the latest round summary.

This memory is optional context only. It is not the canonical finding list,
not proof that any area is safe, and not an execution plan for the next agent.
Do not repeat full findings; findings are stored separately.

Write the updated memory in this exact structure:

# Global Audit Memory

## Scope Touched
- files/contracts/flows touched, with short issue-direction notes

## Issue Directions Seen
- recurring or promising vulnerability directions seen so far

## Useful Context
- concise observations that may help future auditors avoid starting cold

Rules:
- keep it compact
- preserve useful prior context
- remove duplicated or stale detail
- do not claim an area is safe just because it was touched
- do not give step-by-step instructions for the next audit round

## Existing Global Memory
# Global Audit Memory

## Scope Touched
- Queue and signature-queue stack remains central: `queues/DepositQueue.sol`, `queues/RedeemQueue.sol`, `SignatureQueue.sol`, `SignatureDepositQueue.sol`, `SignatureRedeemQueue.sol` (settle/handle/claim accounting, fee-path parity, pause/cancel/checkpoint behavior).
- Share allocation and mint authority path is now top-priority: `managers/ShareManager.sol`, `interfaces/managers/IShareManager.sol`, `modules/ShareModule.sol` (allocated-share consumption, mint auth boundary, claim/lockup side effects).
- Transfer/accounting path stayed active: `libraries/TransferLibrary.sol`, `modules/VaultModule.sol`, `modules/SubvaultModule.sol` (requested-vs-received drift and non-standard ERC20 effects on queue solvency).
- Verifier/permission surfaces were revisited but lighter this round: `permissions/Verifier.sol` and `permissions/*` (intent/payload decoding alignment).
- Broad but shallower coverage continued across fee/risk/oracle/factory/hooks/strategy/config surfaces.

## Issue Directions Seen
- Unauthorized share-allocation consumption via externally callable mint paths is now a confirmed high-severity direction.
- Redeem batch progression without strict asset-receipt validation is a retained direction (underfunded claimable batches and claim-time DoS risk).
- Standard vs signature queue economic/control-path parity (fees, permissions, execution semantics) remains recurring.
- Transfer/accounting fragility under fee-on-transfer/deflationary/non-standard ERC20 behavior remains active.
- Verifier intent/encoding mismatch risk and queue state integrity across emergency/lifecycle transitions remain recurring.
- Payable entrypoint ETH-handling edge cases (unexpected ETH acceptance/stuck funds) remain in-context.

## Useful Context
- Cross-agent convergence remains strongest on multi-contract interactions between queue flows and share-allocation/mint accounting.
- `ShareManager` moved from recurring hotspot to confirmed exploit surface in this round; keep auth and allocation invariants tightly coupled in review context.
- `RedeemQueue` + `ShareModule` handling assumptions around exact transfer receipt remain high signal after retained underfunding/DoS direction.
- Hooks and strategy/factory-adjacent logic were touched with comparatively limited depth; still potentially high-yield due to integration leverage.
- Prior non-retained hotspots (for example transfer-triggered claim/gas behavior in tokenized-share paths) remain unresolved context, not clearance.


## Latest Round Summary
# Round 7 Summary

## Agent: codex_1
- files touched  
  `queues/DepositQueue.sol`, `modules/ShareModule.sol`, `managers/ShareManager.sol`, `managers/RiskManager.sol`, `hooks/BasicRedeemHook.sol`, `queues/RedeemQueue.sol`, `queues/SignatureRedeemQueue.sol`, `libraries/TransferLibrary.sol` (plus interface reads for flow tracing)
- files revisited / highest-attention files  
  `modules/ShareModule.sol`, `queues/DepositQueue.sol`, `managers/ShareManager.sol`, `managers/RiskManager.sol`
- main issue directions investigated  
  queue removal vs claim lifecycle, ETH-sentinel compatibility in redeem liquidity checks, and queue-or-role authorization fallback behavior
- promising but not retained directions  
  early broad hypotheses visible in intermediate output (e.g., missing `setVault` access control) were not kept in final retained findings

## Agent: opencode_1
- files touched  
  broad sweep across managers, queues, modules, hooks, permissions, oracle, factory, strategy, and vault files (including `ShareManager`, `FeeManager`, `RiskManager`, `DepositQueue`, `RedeemQueue`, `ShareModule`, `Oracle`, `Verifier`, `Consensus`, `VaultConfigurator`, etc.)
- files revisited / highest-attention files  
  `managers/FeeManager.sol`, `managers/RiskManager.sol`, `queues/DepositQueue.sol`, `modules/ShareModule.sol`, `oracles/Oracle.sol`, `permissions/Verifier.sol`
- main issue directions investigated  
  fee/oracle update race ideas, queue/accounting consistency, signature queue limits, verifier parsing, hook edge cases, initialization/configuration sequencing
- promising but not retained directions  
  candidate set `F-022`–`F-035` was proposed but none were retained after merge for this round

## Cross-Agent Status
- main overlap in file/area attention  
  strongest overlap was on queue/share/risk surfaces: `DepositQueue`, `RedeemQueue`, `ShareModule`, `RiskManager`, and manager-module interactions
- notable differences in attention  
  `codex_1` narrowed into 3 concrete exploit paths; `opencode_1` explored many additional areas (factory, consensus, hooks, verifier) but outputs were not retained
- underexplored but suspicious files/functions if clearly supported by the logs  
  no new underexplored hotspot was clearly substantiated by merged round outcomes; retained evidence stayed concentrated in queue/share/risk/redeem-liquidity paths

## Retained Findings
- `F-101` (High): removing a deposit queue can strand already-processed but unclaimed deposits because post-removal claim minting fails queue authorization.
- `F-102` (Medium): ETH-sentinel asset mode conflicts with ERC20 `balanceOf` liquidity checks, which can revert and block redeem processing.
- `F-103` (Medium): `onlyQueueOrRole` path can revert on non-queue callers before role fallback, blocking role-authorized emergency accounting calls.


Output only markdown.
