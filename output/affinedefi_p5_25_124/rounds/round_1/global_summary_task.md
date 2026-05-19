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
No global memory yet.

## Latest Round Summary
# Round 1 Summary

## Agent: codex_1
- files touched: `src/strategies/LidoLevV3.sol`, `src/vaults/AffineVault.sol`, `src/interfaces/balancer/IFlashLoanRecipient.sol`
- files revisited / highest-attention files: `LidoLevV3.sol` and `AffineVault.sol`
- main issue directions investigated: Curve unwind slippage and swallowed divest reverts; Balancer flash-loan repayment semantics; distressed-position TVL accounting/underflow; par-value stETH valuation affecting TVL and divest sizing
- promising but not retained directions: `_divest()` / vault accounting mismatch where reported liquidated WETH may exceed transferred WETH

## Agent: opencode_1
- files touched: `src/vaults/AffineVault.sol`, `src/strategies/LidoLevV3.sol`, `src/strategies/BaseStrategy.sol`, `src/strategies/AccessStrategy.sol`, `src/utils/AffineGovernable.sol`, `src/libs/SlippageUtils.sol`, `src/interfaces/balancer/IFlashLoanRecipient.sol`, `src/interfaces/curve/ICurvePool.sol`, `src/strategies/deployed/LidoLevEthStrategy.sol`, `src/interfaces/lido/IWSTETH.sol`
- files revisited / highest-attention files: `LidoLevV3.sol` and `AffineVault.sol`
- main issue directions investigated: slippage and exit-path handling around Curve; strategy upgrade / `createAaveDebt()` trust boundary; vault/strategy operational controls and griefing surfaces
- promising but not retained directions: WSTETH wrapping correctness/slippage, `updateStrategyAllocations()` gas griefing, setter abuse (`setSlippageBps`, `setBorrowBps`), `BaseStrategy.sweep()`, flash-loan callback reentrancy, harvest/front-run griefing

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `LidoLevV3.sol` and `AffineVault.sol`, especially strategy exit/unwind behavior and vault interaction with leveraged positions
- notable differences in attention: codex_1 centered on retained economic/accounting failure modes and Balancer fee handling; opencode_1 ranged more broadly across admin/configuration, wrapping, griefing, and generalized callback safety, with one retained cross-strategy debt-siphoning angle
- underexplored but suspicious files/functions if clearly supported by the logs: current status shows single-agent-only attention on `LidoLevV3.createAaveDebt()`, `LidoLevV3._divest()` return-value accounting, `AffineVault.updateStrategyAllocations()`, and `BaseStrategy.sweep()`

## Retained Findings
- retained issues from this round centered on `LidoLevV3` exit and accounting fragility: Curve near-par unwind thresholds combined with swallowed divest failures, ignored Balancer flash-loan fees, underwater-position TVL underflow, and par-value stETH accounting that can overstate withdrawable WETH
- one additional retained finding covered `createAaveDebt()` allowing any active strategy to induce debt creation, creating a cross-strategy theft path if another strategy is compromised


Output only markdown.
