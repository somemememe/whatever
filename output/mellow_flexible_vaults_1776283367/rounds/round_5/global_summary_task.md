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
- `managers/ShareManager.sol` / `modules/ShareModule.sol` / `queues/DepositQueue.sol` (highest round-4 attention): claim/mint authorization and lockup-timing side effects remain active risk surface.
- Queue stack (`queues/DepositQueue.sol`, `RedeemQueue.sol`, `SignatureQueue.sol` + signature redeem variants): caller/recipient binding, pause/cancel/settle/checkpoint behavior, and claim-path accounting/liveness continue to recur.
- `managers/FeeManager.sol`: fee accrual/update ordering and multi-mint/trigger edge patterns repeatedly examined.
- `managers/RiskManager.sol` / `oracles/Oracle.sol`: oracle-driven conversion/liveness coupling remains high-signal from prior rounds.
- Broader control/config plane touched again (`factories/Factory.sol`, `vaults/VaultConfigurator.sol`, `permissions/*`), but mostly shallow-to-moderate depth this round.
- Limited direct round-4 attention: `modules/ACLModule.sol`, `modules/CallModule.sol`, `modules/SubvaultModule.sol`, `managers/TokenizedShareManager.sol`.

## Issue Directions Seen
- Retained direction: permissionless third-party claim execution can manipulate `targetedLockup` timing (forced lock start / temporary denial-of-use window).
- Signature intent-vs-executor/recipient authorization mismatches remain a recurring direction (especially redeem-side flows).
- Oracle lifecycle actions (including asset removal) causing downstream `convertToShares`-dependent queue/risk liveness failures remain promising.
- Queue state integrity under pause/emergency/cancel/settle/checkpoint transitions continues as a core direction.
- Fee accrual/performance-fee order-of-operations and accounting edge behavior remain recurrent.
- Transfer/accounting fragility with non-standard ERC20 semantics remains relevant.

## Useful Context
- Cross-agent convergence is now strongest around share claim/mint paths (`ShareManager`/`ShareModule`/`DepositQueue`) plus core queue logic; this is where multi-contract exploit chains are most evidenced.
- Round 4 produced one retained addition: third-party claim-triggered lockup timing abuse (`F-015`), while several other round-4 ideas were investigated but not retained.
- Recent broad scans frequently re-surface known patterns; prioritize depth in less-reviewed modules over additional shallow grep passes.
- Governance/config and auxiliary module surfaces are touched but still comparatively under-evidenced versus queues/share/oracle paths.


## Latest Round Summary
# Round 5 Summary

## Agent: codex_1
- files touched: `modules/ShareModule.sol`, `queues/DepositQueue.sol`, `queues/RedeemQueue.sol`, `queues/SignatureDepositQueue.sol`, `queues/SignatureRedeemQueue.sol`, `queues/SignatureQueue.sol`, `permissions/Verifier.sol`, `modules/VaultModule.sol`, `modules/SubvaultModule.sol`, `libraries/TransferLibrary.sol` (plus other in-scope Solidity files scanned).
- files revisited / highest-attention files: signature queue contracts, `permissions/Verifier.sol`, queue fee paths in `DepositQueue`/`RedeemQueue`, vault-subvault transfer/accounting path.
- main issue directions investigated: fee-policy consistency between standard vs signature queues; verifier payload decoding format; transfer/accounting correctness under non-standard ERC20 behavior; payable queue entrypoint ETH handling.
- promising but not retained directions: stale `compactCalls` mapping entry after disallow (reported by agent but not retained in merged round findings).

## Agent: opencode_1
- files touched: broad read across scope, including `modules/ACLModule.sol`, `modules/CallModule.sol`, `modules/SubvaultModule.sol`, `managers/TokenizedShareManager.sol`, `managers/FeeManager.sol`, `permissions/Consensus.sol`, `oracles/Oracle.sol`, `queues/DepositQueue.sol`, `queues/RedeemQueue.sol`, `queues/SignatureQueue.sol`, `queues/SignatureRedeemQueue.sol`, `permissions/Verifier.sol`, `managers/ShareManager.sol`, hooks, factory, and vault files.
- files revisited / highest-attention files: `managers/FeeManager.sol` and iterative edits to its own findings set.
- main issue directions investigated: gas/looping risk in tokenized share transfers; signature queue nonce semantics; factory implementation validation; hook external call handling; oracle submission controls.
- promising but not retained directions: `TokenizedShareManager` transfer-triggered claim loop, non-sequential nonce concern in `SignatureQueue`, factory arbitrary implementation proposal, `LidoDepositHook` return-value handling, oracle spam/rate-limit concerns.

## Cross-Agent Status
- main overlap in file/area attention: queue flows (`DepositQueue`, `RedeemQueue`, signature queues), verifier/permission logic, and fee/accounting paths.
- notable differences in attention: `codex_1` converged on line-level exploitable inconsistencies that were retained; `opencode_1` explored wider hypotheses, many of which were later trimmed/not merged.
- underexplored but suspicious files/functions if clearly supported by the logs: `TokenizedShareManager._update` claim-on-transfer gas behavior remains a reviewed-but-unretained hotspot in this round.

## Retained Findings
- Signature queue execution path bypasses configured deposit/redeem fee hooks used by standard queues (economic inconsistency/fee-capture gap).
- `CUSTOM_VERIFIER` runtime decoding expects a 32-byte-prefixed address layout, conflicting with documented packed encoding and causing call verification failures if operators follow docs.
- Vault/subvault accounting uses requested transfer amounts instead of actual received deltas, creating drift for fee-on-transfer/deflationary tokens.
- Payable ERC20 queue entrypoints can accept nonzero ETH that is not used in ERC20 flow and can become permanently stuck.


Output only markdown.
