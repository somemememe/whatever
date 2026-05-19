# Global Audit Memory

## Scope Touched
- `contracts/Curve.sol` — central hotspot for flash-loan flow, LP mint/burn accounting, and callback-driven state inconsistency
- `contracts/ProportionalLiquidity.sol` — tightly coupled to deposit/withdraw share accounting; relevant to whitelist-era withdrawal behavior
- `contracts/Swaps.sol` — swap execution depends on factory/config wiring; fee-getter integration mismatch is a recurring concern
- `contracts/Assimilators.sol` and `contracts/interfaces/IAssimilator.sol` — core trust boundary because pool logic executes assimilators via `delegatecall`
- `contracts/CurveFactory.sol` and `contracts/interfaces/ICurveFactory.sol` — factory-created pool wiring matters, especially downstream swap compatibility
- `contracts/Orchestrator.sol` — mainly relevant as setup/plumbing for assimilators and approvals rather than as a standalone bug source
- `contracts/Storage.sol` / liquidity-viewing math surfaces — reviewed as supporting context for accounting/state layout, with no retained math-library issue yet
- duplicated deployment/code copies — analysis repeatedly checked parity across both copies, so defects may replicate across deployments

## Issue Directions Seen
- Flash-loan callback reentrancy against temporarily distorted balances/share math, especially around deposits and LP minting
- Assimilator trust and upgradeability risk from external modules reached through `delegatecall`, with potential storage and asset compromise
- Factory/pool/swap integration mismatches where constructor or interface assumptions break live swap paths
- Whitelist-stage transfer and withdrawal accounting mismatches between original depositor tracking and current LP ownership
- Broader admin/configuration/control-surface ideas were explored, but the durable pattern is “miswiring and privileged module trust” more than simple owner abuse

## Useful Context
- Cross-agent overlap was strongest on `Curve.sol`, `ProportionalLiquidity.sol`, `Assimilators.sol`, `CurveFactory.sol`, and swap/liquidity paths
- The most durable findings came from cross-contract interactions, not isolated single-function edge cases
- Many secondary hypotheses around math, deadlines, duplicate pools, oracle assumptions, and generic DoS were reviewed but did not mature into retained issues
- `Orchestrator.sol` and storage/math files mostly served as context for wiring and accounting, not primary vulnerability centers in the latest round
- Duplicate code/deployment structure matters: retained issues were considered likely to apply across mirrored copies unless deployment-specific wiring differs
