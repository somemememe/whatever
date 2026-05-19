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
- `modules/ShareModule.sol` / `managers/ShareManager.sol` / `managers/TokenizedShareManager.sol`: transfer/claim flow logic, whitelist enforcement behavior, auto-claim side effects on liveness.
- `queues/DepositQueue.sol` / `queues/SignatureDepositQueue.sol` / `queues/SignatureRedeemQueue.sol` / `queues/SignatureQueue.sol`: cancellation/accounting consistency, signature-gated queue execution, pause-path coverage.
- `permissions/Consensus.sol`: signer-set/authorization correctness under multisig-style validation.
- `managers/RiskManager.sol` / `oracles/Oracle.sol`: initialization-time vault binding and privileged configuration surfaces.
- `modules/VaultModule.sol` / `managers/FeeManager.sol` (+ related interfaces/hooks/libraries): integration and accounting/access-control review, mostly as exploit-path support.

## Issue Directions Seen
- Signature authorization robustness, especially signer uniqueness and replay/validation edge cases.
- Queue state/accounting integrity around cancel/checkpoint/index handling.
- Pause and emergency-control completeness for signature-driven flows.
- Transfer-path policy enforcement correctness (whitelist/permission inversion risks).
- Gas/liveness degradation from implicit claim loops and batched side effects.
- One-time initialization and `setVault`-style binding races during deployment/bootstrap.

## Useful Context
- Strong cross-agent overlap on `setVault` initialization risk and Share/TokenizedShare claim-path liveness concerns.
- Codex pass emphasized concrete exploit chains in consensus, queue cancellation, whitelist logic, and signature pause coverage.
- Opencode pass covered nearly all contracts and surfaced broader speculative candidates; highest signal remained in overlapping core modules/managers/queues.
- `queues/SignatureQueue.sol` and `modules/VaultModule.sol` drew attention but were comparatively less converted into retained outcomes, so still useful for targeted re-validation.


## Latest Round Summary
# Round 2 Summary

## Agent: codex_1
- files touched  
  `managers/FeeManager.sol`, `modules/ShareModule.sol`, `managers/RiskManager.sol`, `modules/VaultModule.sol`, `hooks/BasicRedeemHook.sol`, `queues/RedeemQueue.sol`, `queues/DepositQueue.sol`, `queues/SignatureDepositQueue.sol`, `libraries/TransferLibrary.sol` (plus broad initial scope reads).
- files revisited / highest-attention files  
  Highest attention was on `FeeManager`, `ShareModule`, `RiskManager`, `VaultModule`, `BasicRedeemHook`, and deposit/redeem queue + transfer paths (with line-level rechecks).
- main issue directions investigated  
  Fee accrual/state-update coupling across report assets; performance-fee trigger logic; subvault allowlist effects on pull flows; redeem hook liquidity assumptions vs risk checks; ERC20 transfer-accounting assumptions.
- promising but not retained directions  
  No additional non-retained direction was explicit in the log beyond the five finalized findings.

## Agent: opencode_1
- files touched  
  Very broad sweep across most in-scope modules, managers, queues, hooks, factory, oracle, permissions, verifier/protocol adapters, and strategy files.
- files revisited / highest-attention files  
  Notable focus on `FeeManager`, `ShareModule`, `RiskManager`, `VaultModule`, queue contracts, `TransferLibrary`, `Oracle`, and permissions/verifier stack.
- main issue directions investigated  
  Setup/control-plane risks (`setVault`), hook `delegatecall` execution model, fee/state update behavior, oracle timeout/suspicion logic, gas/DoS surfaces, queue accounting/precision paths.
- promising but not retained directions  
  Reported hypotheses around permissionless vault replacement, hook delegatecall abuse/silent failure, oracle timeout bypass, factory race, and rounding/gas concerns were not retained in merged findings for this round.

## Cross-Agent Status
- main overlap in file/area attention  
  Strong overlap on `FeeManager`, `ShareModule`, `RiskManager`, `VaultModule`, `DepositQueue`/`RedeemQueue`, and `TransferLibrary`.
- notable differences in attention  
  `codex_1` concentrated on concrete exploitable accounting/lockup/DoS paths tied to fee logic and subvault asset handling; `opencode_1` covered a wider architecture surface (oracle, factory, permissions/verifiers) with more speculative outputs.
- underexplored but suspicious files/functions if clearly supported by the logs  
  `Oracle.sol` and `Factory.sol` received attention mainly from `opencode_1` but produced no retained findings this round.

## Retained Findings
- `F-007`/`F-008`: high-severity fee logic flaws in `FeeManager` causing repeated protocol over-accrual and performance-fee charging on drawdowns.
- `F-009`/`F-010`: subvault allowlist interactions can lock disallowed-held assets and enable redeem-flow DoS via dusting disallowed subvaults.
- `F-011`: deposit accounting assumes exact ERC20 transfer amounts, creating dilution/deficit risk for fee-on-transfer assets.


Output only markdown.
