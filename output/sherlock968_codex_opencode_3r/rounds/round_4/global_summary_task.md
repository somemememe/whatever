You maintain a concise global audit memory for future audit agents.

Update the existing global memory by folding in durable observations from the
latest round summary. The goal is an accumulated cross-round audit view, not a
per-round recap.

This memory is optional context only. Findings are stored separately.

Write the updated memory in this exact structure:

# Global Audit Memory

## Scope Touched
- files/contracts/flows that have mattered across rounds, with short issue-direction notes

## Issue Directions Seen
- recurring or promising vulnerability directions seen across the audit

## Useful Context
- compact cross-round observations 

Rules:
- keep it compact
- preserve useful prior context while integrating new durable observations
- prefer stable cross-round patterns over latest-round details
- fold repeated wording into a single clearer observation
- keep the memory descriptive rather than prescriptive

## Existing Global Memory
# Global Audit Memory

## Scope Touched
- `FluidLocker.sol`: sustained hotspot for staking/LP accounting coupling, unlock/unstake liveness, and dependence on external pool/unit state.
- `StakingRewardController.sol`: core integration surface for tax-adjustment/distribution timing and downstream locker unlockability.
- `FluidEPProgramManager.sol`: highest-signal program-manager hotspot; repeated focus on funding stream lifecycle (`startFunding`/`stopFunding`), end-of-program handling, and residual flow state.
- `EPProgramManager.sol`: persistent auth/control-plane focus, including durable program-creation ID-squatting risk.
- `Fontaine.sol`: repeatedly relevant via timing/control behavior and immutable pool-address snapshot coupling with locker/controller setup.
- `SuperTokenV1Library.sol` + managers: recurring integration-trust surface around framework-address caching/assumptions, with mostly integration-level risk.
- `MacroForwarder.sol`, vesting contracts/factories, peripherals: repeatedly scanned, comparatively lower retained signal.

## Issue Directions Seen
- Economic/state divergence and liveness failures from cross-contract accounting/unit dependencies.
- Funding lifecycle fragility in program managers, especially stream state that can outlive intended program end without explicit stop/cancel actions.
- Initialization/snapshot ordering hazards (immutable/cached addresses set before full system readiness).
- Permissionless control-plane timing games and resource-squatting outcomes.
- Signature-domain/replay-boundary weakness as a recurring auth direction.
- Integration trust assumptions around cached protocol/framework addresses.

## Useful Context
- Strongest cross-round convergence remains on end-to-end `FluidLocker` + `StakingRewardController` + program-manager interactions, not isolated single-contract bugs.
- Newly reinforced durable signal: `FluidEPProgramManager` funding streams may continue past intended duration unless actively stopped, making lifecycle termination behavior a central cross-round concern.
- Highest-confidence retained themes are mechanism-level (state coupling, liveness, control authority, initialization order) rather than one-off checklist findings.
- Some areas are repeatedly read with low retained yield (`MacroForwarder`, large parts of `SuperTokenV1Library`, vesting/peripheral files) versus core locker/program-manager pathways.


## Latest Round Summary
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


Output only markdown.
