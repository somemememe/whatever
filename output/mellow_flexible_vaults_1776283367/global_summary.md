# Global Audit Memory

## Scope Touched
- Core hotspot remains queue/share lifecycle and privilege boundaries: `queues/DepositQueue.sol`, `queues/RedeemQueue.sol`, `queues/SignatureDepositQueue.sol`, `queues/SignatureRedeemQueue.sol`, `queues/SignatureQueue.sol`, `modules/ShareModule.sol`, `managers/ShareManager.sol`, plus factory-controlled queue deployment/ownership in `factories/Factory.sol`.
- Authorization/accounting fallback surface remains important in manager paths, especially `managers/RiskManager.sol` and queue-trusted manager entrypoints.
- Transfer/native-asset handling is a persistent risk area: `libraries/TransferLibrary.sol` and ETH-sentinel/plain-ETH behavior across redeem/signature flows.
- Oracle first-report semantics remain relevant in `oracles/Oracle.sol`, but secondary to queue/share privilege and flow integrity.
- Peripheral but repeatedly scanned, lower-evidence surfaces: hooks and verifier/permission components (e.g., `hooks/LidoDepositHook.sol`, `permissions/Verifier.sol`, `permissions/protocols/OwnedCustomVerifier.sol`).

## Issue Directions Seen
- Confirmed: processed-but-unclaimed deposits can be stranded when claim minting still depends on queue authorization after queue removal.
- Confirmed: native-asset/ETH handling mismatches can DoS redeem paths (ERC20 `balanceOf` assumptions and signature-redeem plain-ETH reception incompatibility).
- Confirmed: `onlyQueueOrRole`-style sequencing can revert before role fallback, breaking emergency role-authorized accounting paths.
- Confirmed recurring: share `_update`/claim ordering bugs can bypass lockup-style restrictions.
- Confirmed recurring: signature-vs-standard queue parity gaps can create authorization/whitelist bypasses.
- Confirmed recurring: blacklist enforcement asymmetry in share transfer flows.
- Newly strengthened/confirmed: queue trust boundary is upgradeability-sensitive; creator-controlled queue proxy admin can mutate trusted queue logic and abuse queue-only privileged manager/module paths.
- Recurring: oracle first-report on new assets can force suspicious-state dependence on explicit acceptance.
- Lower-signal recurring: verifier/encoding/init-validation edge cases and hook-specific integration edge paths.

## Useful Context
- Cross-round convergence is strongest at queue/module/manager seams where trust assumptions propagate; `ShareModule.sol`, `ShareManager.sol`, queue contracts, and `Factory.sol` are persistent context hubs.
- A durable pattern is boundary fragility: authorization continuity, fallback ordering, mirrored-path parity, and asset-mode assumptions (ERC20 vs native ETH).
- Queue identity alone is not a stable trust anchor when queue upgrade/admin control is externalized.
- Oracle/hook/verifier areas remain useful adjacent context, but evidence density is consistently lower than core queue/share control paths.
