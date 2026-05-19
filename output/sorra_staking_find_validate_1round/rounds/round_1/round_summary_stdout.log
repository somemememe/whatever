# Round 1 Summary

## Agent: codex
- files touched: `onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol`, `onchain_auto/0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/interfaces/IPoolExtension.sol`, plus supporting reads of `@openzeppelin/contracts/access/Ownable.sol` and `@openzeppelin/contracts/utils/ReentrancyGuard.sol`
- files revisited / highest-attention files: `sorraStaking.sol` was the clear focus and was reopened with line numbers; `IPoolExtension.sol` was revisited to validate the external hook surface
- main issue directions investigated: staking state transitions in `deposit()`/`withdraw()`, reward accrual and pool solvency, fee-on-transfer accounting mismatch, owner emergency withdrawal authority, and extension-hook behavior around `vaultExtension.setShare()`
- promising but not retained directions: extension-hook gas exhaustion / withdrawal bricking, swallowed extension-call failures causing external ledger desync, and the exact-maturity `>=` vs `>` mismatch; the agent also raised a pool-cap/reward-insolvency issue that overlaps with the retained shared-pool reward funding finding

## Cross-Agent Status
- main overlap in file/area attention: single-agent round; attention was concentrated on `sorraStaking.sol`, especially withdrawal, reward, accounting, and owner-control paths
- notable differences in attention: no cross-agent divergence in this round
- underexplored but suspicious files/functions if clearly supported by the logs: no additional clearly supported underexplored hotspot beyond `sorraStaking.sol`; the owner-set extension path (`setVaultExtension` / external share updates) was examined but not retained

## Retained Findings
- repeated reward extraction via partial matured withdrawals was retained as the top issue
- shared-token reward funding was retained as a solvency issue because rewards are paid from the same pool backing principal
- fee-on-transfer token handling was retained due to accounting exceeding real received assets
- owner emergency withdrawal authority was retained because it can remove user-backed funds without liability adjustment
