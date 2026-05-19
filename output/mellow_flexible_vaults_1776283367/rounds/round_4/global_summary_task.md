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
- `queues/SignatureRedeemQueue.sol` / `queues/SignatureQueue.sol` (+ signature queue variants): recipient/caller authorization binding and signed-order execution semantics remain a primary risk surface.
- `queues/DepositQueue.sol` / `queues/RedeemQueue.sol`: settlement/cancel/checkpoint integrity and index/accounting edge cases continue to recur.
- `managers/RiskManager.sol` + `oracles/Oracle.sol`: oracle-driven conversion dependencies (including asset removal effects) and revert propagation into queue flows are now high-signal.
- `managers/FeeManager.sol`: accrual/performance-fee math and state-update ordering remain a persistent direction.
- `modules/ShareModule.sol` / `managers/ShareManager.sol` / `managers/TokenizedShareManager.sol`: claim/mint/share-allocation side effects and liveness/economic edge cases remain relevant.
- `modules/VaultModule.sol` / `managers/RiskManager.sol`: subvault allowlist composition with redeem/asset movement still implicated in lockup-style behavior.
- `libraries/TransferLibrary.sol`: non-standard ERC20 receipt/accounting assumptions remain important for dilution/DoS analysis.
- lightly touched this round: `Factory.sol`, `VaultConfigurator.sol`, `permissions/Verifier.sol` (low-depth coverage, no retained outcomes).

## Issue Directions Seen
- Signature authorization mismatches between signed intent and on-chain actor/recipient binding (now reinforced by retained redeem-flow auth issue).
- Oracle lifecycle/control actions (notably asset removal) causing downstream conversion reverts and queue/risk liveness failures.
- Queue state integrity and pause/emergency-path completeness under cancel/settle/checkpoint transitions.
- Fee accrual and performance-fee trigger/order-of-operations errors.
- Share/deposit accounting fragility with non-standard ERC20 transfer semantics.
- Control-plane/initialization assumptions around privileged wiring and allowlist-governed asset routes.

## Useful Context
- Cross-agent convergence is strongest on signature queues, core queues, `RiskManager`, and `Oracle`; these interfaces create the most credible multi-contract failure chains.
- Round-3 retained signal concentrated on: (1) recipient-bound authorization in signature redeem paths, and (2) oracle asset-removal fallout on `convertToShares`-dependent operations.
- Prior hypotheses around claim-path gas/liveness, share-allocation minting abuse, and oracle/report edge behavior were investigated with mixed retention; treat as context, not closure.
- Broader config/governance surfaces (`Factory`/`VaultConfigurator`/`Verifier`) were scanned but remain comparatively under-evidenced.


## Latest Round Summary
# Round 4 Summary

## Agent: codex_1
- files touched: broad scan of `managers/*.sol`, `modules/*.sol`, `queues/*.sol`, `permissions/*.sol`, `oracles/*.sol`, `factories/*.sol`; explicitly read `managers/ShareManager.sol`, `managers/RiskManager.sol`, `modules/ShareModule.sol`, `interfaces/managers/IShareManager.sol`, `interfaces/managers/IFeeManager.sol`, `interfaces/permissions/IVerifier.sol`, `interfaces/oracles/IOracle.sol`
- files revisited / highest-attention files: `managers/ShareManager.sol`, `modules/ShareModule.sol`, `queues/DepositQueue.sol`
- main issue directions investigated: authorization on share mint/claim flows, targeted lockup timing abuse, initialization/permission boundaries, factory proposal spam/state growth
- promising but not retained directions: unrestricted `mintAllocatedShares` theft path and factory `proposeImplementation` state-bloat griefing were proposed by this agent but not retained after merge

## Agent: opencode_1
- files touched: wide read across core contracts including `permissions/Consensus.sol`, `queues/DepositQueue.sol`, `queues/RedeemQueue.sol`, `queues/SignatureQueue.sol`, `modules/ShareModule.sol`, `managers/ShareManager.sol`, `managers/FeeManager.sol`, `managers/RiskManager.sol`, `oracles/Oracle.sol`, `factories/Factory.sol`, `vaults/Vault.sol`, `vaults/VaultConfigurator.sol`, hooks and libraries
- files revisited / highest-attention files: `managers/ShareManager.sol`, `managers/FeeManager.sol`, `modules/ShareModule.sol`
- main issue directions investigated: transfer permission checks, fee accrual/update paths, queue pause/signature behavior, claim/accounting loop complexity
- promising but not retained directions: outputs mainly repeated previously known issues (transfer whitelist inversion, multi-mint protocol fee, gas-heavy claim/accounting loops) and were not retained as new merged findings

## Cross-Agent Status
- main overlap in file/area attention: strong overlap on `ShareManager` + `ShareModule` + queue claim paths, with both also reviewing fee/queue logic
- notable differences in attention: codex_1 emphasized concrete permissionless-claim exploitation and lockup timing; opencode_1 emphasized broad grep-driven coverage and mostly known-pattern/gas-complexity checks
- underexplored but suspicious files/functions if clearly supported by the logs: this round shows limited direct attention on `modules/ACLModule.sol`, `modules/CallModule.sol`, `modules/SubvaultModule.sol`, and `managers/TokenizedShareManager.sol`

## Retained Findings
- `F-015` retained (Medium, medium confidence): permissionless third-party claiming (`ShareModule.claimShares(account)` / `DepositQueue.claim(account)`) can force when `targetedLockup` starts by triggering mint updates to `lockedUntil`, enabling targeted temporary denial-of-use for victim transfers/burns.


Output only markdown.
