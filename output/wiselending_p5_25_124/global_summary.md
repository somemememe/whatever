# Global Audit Memory

## Scope Touched
- `contracts/WiseLending.sol`: primary hotspot for lending-state transitions, share mint/burn accounting, liquidation bookkeeping, and position token-array lifecycle
- `contracts/WiseCore.sol`: core accounting and pool-state interaction surface, especially around accrual/synchronization assumptions
- `contracts/MainHelper.sol`: helper-layer math and exact-amount flow behavior repeatedly tied to rounding and zero-share edge cases
- `contracts/WiseLendingDeclaration.sol`: useful for inheritance/state-layout review around locking, position state, and shared storage assumptions
- `contracts/WiseLowLevelHelper.sol`: secondary hotspot for low-level transfer/accounting behavior and non-standard token assumptions
- `contracts/PoolManager.sol`: secondary hotspot for pool/configuration bounds and control-surface assumptions
- admin/control surfaces (`OwnableMaster.sol` and related assignment paths): reviewed for security-role assignment, emergency controls, and configuration trust assumptions

## Issue Directions Seen
- Exact-amount borrow/withdraw paths are sensitive to rounding-to-zero share outcomes and accounting bypasses
- Pool synchronization and interest-accrual timing create edge cases, especially when rounding leaves timestamps/state partially stale
- ETH/WETH deposit paths may diverge from standard pool-sync assumptions and can over-credit if synchronization is skipped
- Token transfer accounting relies on standard ERC20 behavior; fee-on-transfer or otherwise non-standard tokens remain a recurring risk direction
- Liquidation logic is a repeated scrutiny area, especially sequencing between accounting updates and token/share bookkeeping
- Position/NFT bookkeeping has persistent complexity around token-array growth, stale entries, locking/isolation state, and DOS-style state pollution
- Protocol-control and configuration surfaces were explored repeatedly, but current durable signal is weaker than the core accounting paths

## Useful Context
- Cross-round attention is concentrated on the lending/accounting core: `WiseLending.sol`, `WiseCore.sol`, and `MainHelper.sol`
- The strongest retained signal so far is accounting correctness rather than governance/admin compromise
- Secondary files worth remembering as context even without retained findings yet are `WiseLowLevelHelper.sol`, `PoolManager.sol`, and `WiseLendingDeclaration.sol`
- Reviewed but currently unretained themes include pause/emergency design, event coverage, role assignment, collateral-factor bounds, receive-path reentrancy, and fee-manager/position-lock assumptions
