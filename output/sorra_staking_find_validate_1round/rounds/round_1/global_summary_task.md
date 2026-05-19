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
- `0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/sorraStaking.sol` - core audit focus across staking lifecycle; recurring concern around deposit, reward accrual, partial/full withdraw, and emergency exit logic
- `0x5d16b8ba2a9a4eca6126635a6ffbf05b52727d50/contracts/interfaces/IPoolExtension.sol` - extension-linked behavior was glanced at but remains comparatively underexplored versus core staking flows
- OpenZeppelin ERC20 / ownership helpers - reviewed mainly as supporting context for token-transfer assumptions and owner powers, not as primary issue sources

## Issue Directions Seen
- Reward-accounting flaws tied to staking state transitions, especially around partial withdrawals and repeated realization of matured rewards
- Pool solvency risk from paying rewards out of the same token balance that backs user principal, creating cross-user subsidization
- Token accounting mismatch when staking token behavior deviates from plain ERC20 transfers, especially fee-on-transfer cases
- Strong owner-control / fund-custody risk concentrated in emergency withdrawal style paths
- Secondary direction worth keeping in view: extension/interface-linked behavior around `IPoolExtension` remains less exercised than the main staking contract

## Useful Context
- Audit attention is heavily concentrated on `sorraStaking.sol`; most durable risk comes from internal accounting and fund-flow design rather than imported library code
- The most persistent themes are insolvency, principal leakage, and reward double-counting rather than access-control complexity
- Supporting library review did not surface independent issues, but it helped frame assumptions about ERC20 transfer semantics and owner authority
- Latest retained findings all map back to the same core pattern: reward and withdrawal logic is tightly coupled to the live token balance, making accounting correctness the central cross-round concern


## Latest Round Summary
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


Output only markdown.
