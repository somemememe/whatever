# Round 1 Summary

## Agent: codex_1
- files touched: scope-wide contract inventory, with retained findings concentrated in `contracts/MainHelper.sol`, `contracts/WiseCore.sol`, and `contracts/WiseLending.sol`
- files revisited / highest-attention files: `MainHelper.sol`, `WiseCore.sol`, `WiseLending.sol`; `WiseLendingDeclaration.sol` was also explicitly opened early for inheritance/state review
- main issue directions investigated: share/accounting rounding on exact-amount borrow/withdraw flows; pool sync and interest accrual edge cases; WETH deposit synchronization differences; transfer-accounting assumptions for non-standard ERC20s; liquidation bookkeeping; position token-array lifecycle/limits
- promising but not retained directions: none clearly visible in the log beyond the findings that were retained

## Agent: opencode_1
- files touched: all 16 in-scope Solidity files were read, including the full core set plus interfaces and transfer helpers
- files revisited / highest-attention files: `WiseLending.sol`, `WiseCore.sol`, `MainHelper.sol`, `WiseLowLevelHelper.sol`, `WiseLendingDeclaration.sol`, `PoolManager.sol`, `OwnableMaster.sol`
- main issue directions investigated: admin/security contract assignment, liquidation sequencing, fee-share math, receive-path reentrancy, approval validation, pause/emergency controls, collateral-factor bounds, fee-manager assumptions, isolation/locking storage usage
- promising but not retained directions: malicious `setSecurity` assignment, liquidation state-before-transfer inconsistency, fee-share division-by-zero edge case, receive-function reentrancy, 100% collateral-factor allowance, missing events / no pause / irreversible renounce, fee-manager NFT assumptions, and `positionLocked` dual-use concerns

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on the lending/accounting core in `WiseLending.sol`, `WiseCore.sol`, and `MainHelper.sol`
- notable differences in attention: `codex_1` focused on exploitable accounting and synchronization mechanics that produced the retained findings; `opencode_1` spent more attention on admin/configuration, liquidation ordering, and protocol-control surfaces
- underexplored but suspicious files/functions if clearly supported by the logs: `WiseLowLevelHelper.sol`, `PoolManager.sol`, and `WiseLendingDeclaration.sol` received attention from `opencode_1` but did not produce retained findings; they remain current-status secondary hotspots from this round

## Retained Findings
- Retained findings from this round all came from `codex_1` and centered on core accounting correctness: zero-share exact-amount borrow/withdraw bypasses, repeated re-accrual when fee rounding leaves timestamps stale, unsynchronized `depositExactAmountETHMint` over-minting, non-standard token transfer accounting gaps, liquidation share-bookkeeping mismatch, and position token-array overflow / stale-entry DOS.
