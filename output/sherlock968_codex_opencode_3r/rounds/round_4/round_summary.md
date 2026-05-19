# Round 4 Summary

## Agent: codex_1
- files touched
  - Broad scope scan; highest activity in `FluidEPProgramManager.sol`, `FluidLocker.sol`, and `SuperTokenV1Library.sol`, plus targeted checks in `EPProgramManager.sol` and `FluidLockerFactory.sol`.
- files revisited / highest-attention files
  - `superfluid-finance/fluid/packages/contracts/src/FluidEPProgramManager.sol`
  - `superfluid-finance/fluid/packages/contracts/src/FluidLocker.sol`
  - `superfluid-org/protocol-monorepo/packages/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol`
- main issue directions investigated
  - Shared subsidy stream accounting vs per-program requested subsidy rates.
  - Token/pool compatibility between program creation/funding and locker claim/connect flow.
  - Signature hashing robustness in batch unit updates.
  - ETH withdrawal reliability via `transfer`.
- promising but not retained directions
  - `F-015` (packed-encoding ambiguity in batch signatures) was proposed but not retained.
  - `F-017` (`transfer`-based ETH withdrawal lock risk) was proposed but not retained.

## Agent: opencode_1
- files touched
  - Read all 12 Solidity files in scope, including core manager/locker contracts, vesting, interfaces, and Superfluid library/forwarder files.
- files revisited / highest-attention files
  - No clear revisit/deep-focus pattern shown in the log beyond full-file reads.
- main issue directions investigated
  - Broad initial coverage/read-through of in-scope contracts.
- promising but not retained directions
  - No concrete candidate findings were output in this round log.

## Cross-Agent Status
- main overlap in file/area attention
  - Both agents covered the same scoped Solidity set, with shared attention on `FluidEPProgramManager.sol`, `FluidLocker.sol`, and Superfluid library integration points.
- notable differences in attention
  - `codex_1` performed targeted exploit-path analysis and produced candidate findings; `opencode_1` log shows primarily ingestion/reading without finalized issues.
- underexplored but suspicious files/functions if clearly supported by the logs
  - Current retained set is concentrated in manager/locker/subsidy flow interactions; other scoped modules (`Fontaine.sol`, `StakingRewardController.sol`, vesting contracts) appear comparatively less evidenced in retained outcomes this round.

## Retained Findings
- `F-014` (Medium): Shared subsidy flow can be reduced/zeroed incorrectly when stop/cancel subtracts requested per-program subsidy from a lower actual stream, impacting still-active programs.
- `F-016` (Medium): Non-`FLUID` program tokens are accepted but locker reward/connection paths are `FLUID`-centric, creating incompatible funding/claim behavior and potential stuck rewards.
