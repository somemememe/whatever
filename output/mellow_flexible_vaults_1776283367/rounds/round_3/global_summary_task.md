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
- `managers/FeeManager.sol`: fee accrual/reporting coupling and performance-fee trigger behavior (including loss-period charging direction).
- `modules/ShareModule.sol` / `managers/ShareManager.sol` / `managers/TokenizedShareManager.sol`: transfer/claim flow side effects, whitelist-policy enforcement, liveness pressure from claim paths.
- `managers/RiskManager.sol` / `modules/VaultModule.sol`: privileged control-plane wiring (`setVault`/bootstrap assumptions), subvault allowlist interactions with asset movement.
- `queues/DepositQueue.sol` / `queues/RedeemQueue.sol` / `queues/SignatureDepositQueue.sol` / `queues/SignatureRedeemQueue.sol` / `queues/SignatureQueue.sol`: queue accounting/cancellation/checkpoint integrity, signature-gated execution, pause-path completeness.
- `hooks/BasicRedeemHook.sol`: hook liquidity assumptions and interaction boundaries with risk checks.
- `libraries/TransferLibrary.sol`: ERC20 transfer-accounting assumptions (exact-amount vs received-amount behavior).
- `permissions/Consensus.sol`: signer-set authorization correctness under multisig-style validation.
- `oracles/Oracle.sol` / factory surface: timeout/suspicion and deployment/control-plane hypotheses were examined but not retained this round.

## Issue Directions Seen
- Fee math/state-update ordering flaws: over-accrual and incorrect performance-fee charging conditions.
- Subvault allowlist + redeem path composition: asset lockup and dust-induced DoS vectors.
- Deposit/share accounting under non-standard ERC20 semantics (fee-on-transfer/short-receipt dilution risk).
- Signature authorization robustness: signer uniqueness, replay/validation edge cases.
- Queue state integrity: cancel/index/checkpoint precision and pause/emergency coverage gaps.
- Initialization/control-plane race windows around one-time vault binding and privileged setup.

## Useful Context
- Highest cross-agent signal converged on `FeeManager`, `ShareModule`, `RiskManager`, `VaultModule`, queue contracts, and `TransferLibrary`.
- This round’s retained outcomes concentrated on fee logic, subvault-allowlist redeem behavior, and transfer-accounting assumptions; broader oracle/factory/permission hypotheses saw less retention.
- Prior-round concerns on claim-path liveness and signature-queue safety remain relevant context, not closure.
- `Oracle.sol` and factory/control-plane paths were explored with mixed conviction and may still warrant targeted re-validation if new evidence appears.


## Latest Round Summary
# Round 3 Summary

## Agent: codex_1
- files touched: `queues/SignatureRedeemQueue.sol`, `queues/SignatureQueue.sol`, `queues/DepositQueue.sol`, `queues/RedeemQueue.sol`, `queues/SignatureDepositQueue.sol`, `managers/RiskManager.sol`, `oracles/Oracle.sol` (and checked file inventory)
- files revisited / highest-attention files: `SignatureQueue` + `SignatureRedeemQueue` auth flow; `Oracle` + `RiskManager` conversion/revert path; queue settlement/cancel paths in `DepositQueue`/`RedeemQueue`
- main issue directions investigated: signature-order authorization binding; oracle asset-removal effects on downstream queue/risk flows; share-allocation mint path in `ShareManager`
- promising but not retained directions: reported `F-012` (`ShareManager.mintAllocatedShares` theft/DoS path) but it was not retained in merged findings

## Agent: opencode_1
- files touched: broad scan across queues, managers, modules, oracle, permissions, factory/configurator (`Consensus`, `DepositQueue`, `SignatureQueue`, `FeeManager`, `ShareManager`, `RiskManager`, `ShareModule`, `RedeemQueue`, `Oracle`, `Vault`, `Factory`, `VaultConfigurator`, `VaultModule`, `Verifier`, etc.)
- files revisited / highest-attention files: `RiskManager.sol`, `Oracle.sol`, `DepositQueue.sol`, `ShareModule.sol`, `FeeManager.sol`, `SignatureQueue.sol`
- main issue directions investigated: oracle first-report handling; RiskManager limit/accounting behavior; gas-scalability of claim aggregation; fee accrual growth over time
- promising but not retained directions: none of opencode_1’s submitted findings were retained; one direction duplicated a known issue (`DepositQueue.cancelDepositRequest` index mismatch)

## Cross-Agent Status
- main overlap in file/area attention: strong overlap on queues (`DepositQueue`, `RedeemQueue`, signature queues), `RiskManager`, and `Oracle`
- notable differences in attention: codex_1 focused on exploit-chain validation with concrete queue/risk interactions; opencode_1 covered wider economic/gas patterns and config-related logic
- underexplored but suspicious files/functions if clearly supported by the logs: `Factory.sol`, `VaultConfigurator.sol`, and `permissions/Verifier.sol` were touched only lightly with no retained outcomes this round

## Retained Findings
- `F-013`: Signature redeem flow allows burning shares from `order.recipient` without recipient-bound on-chain authorization, if signer-approved order data is provided by `order.caller`.
- `F-014`: Oracle asset removal can make `RiskManager.convertToShares` revert for that asset, which can brick queue/risk operations and create realistic fund-lock conditions.


Output only markdown.
