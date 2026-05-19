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
