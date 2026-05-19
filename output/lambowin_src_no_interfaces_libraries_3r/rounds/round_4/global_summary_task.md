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
- Core launch stack remains the persistent center: `VirtualToken.sol`, `LamboFactory.sol`, `LamboVEthRouter.sol`, `rebalance/LamboRebalanceOnUniwap.sol`.
- Supporting surfaces repeatedly reviewed with lower retained yield: `LamboToken.sol`, `Utils/LaunchPadUtils.sol`, and launchpad utility/pair assumptions.
- Cross-contract path under sustained focus: launch creation (clone/pair setup) -> virtual debt/accounting lifecycle -> router settlement/quotes -> rebalance execution.
- `LamboFactory.sol` launch creation is a confirmed critical hotspot (LP/pair handling fragility, including predictable-address pre-creation DoS vector).
- `rebalance/LamboRebalanceOnUniwap.sol` is now a confirmed high-signal hotspot (execution with weak output/slippage enforcement).

## Issue Directions Seen
- Recurring accounting-consistency risk between virtual mint/burn/debt state and real transferable backing remains a core direction.
- Launch-flow fragility is a durable pattern: initialization/pool creation sequencing and deterministic address assumptions can brick or DoS launches.
- Router/rebalance execution semantics vs market reality is a recurring risk direction, especially quote-to-execution mismatch and transfer assumptions.
- Slippage/MEV exposure in rebalance moved from exploratory to retained direction (insufficient caller-provided output protection).
- Frequently explored but lower-retention directions: generic deadline/pause hygiene, callback/profit-accounting edge cases, approval/trust framing, and broad owner-centralization themes.
- Upgradeable/initializer/deployment-assumption concerns recur, but round-level hypotheses here have mostly remained unretained.

## Useful Context
- Highest-value retained results continue to come from concrete end-to-end call-path validation rather than checklist-style scanning.
- Cross-agent convergence remains strongest at factory/router/rebalance intersections; broad rebalance hypothesis sweeps tend to produce many unretained claims.
- `LamboToken.sol`, `Utils/LaunchPadUtils.sol`, and parts of `VirtualToken.sol` are repeatedly touched but have produced fewer durable retained outcomes than factory launch flow and rebalance execution boundaries.


## Latest Round Summary
# Round 4 Summary

## Agent: codex_1
- files touched: `LamboFactory.sol`, `LamboToken.sol`, `LamboVEthRouter.sol`, `VirtualToken.sol`, `Utils/LaunchPadUtils.sol`, `rebalance/LamboRebalanceOnUniwap.sol` (plus limited interface/library context reads)
- files revisited / highest-attention files: `LamboVEthRouter.sol`, `rebalance/LamboRebalanceOnUniwap.sol`, `VirtualToken.sol`
- main issue directions investigated: ETH/vETH cashIn-cashOut assumptions across router+rebalance, rebalance preview signal integrity, routing bitmask handling, config/address trust boundaries, quote-token routing scope, payable loan edge cases
- promising but not retained directions: hardcoded integration-address misdeployment risk, `directionMask` bit-injection claim, `takeLoan` payable ETH-trap claim, unrestricted `quoteToken` as generic vETH bridge

## Agent: opencode_1
- files touched: same six in-scope contracts were read; broad `**/*.sol` glob plus grep passes (`approve`, `repayLoan`, `receive()`, `uniswapV3SwapTo`)
- files revisited / highest-attention files: `VirtualToken.sol`, `rebalance/LamboRebalanceOnUniwap.sol`, `LamboVEthRouter.sol`
- main issue directions investigated: token burn/transfer ordering, rebalance slippage/min-return behavior, loan repayment accounting/permissions, pool/direction parameter validation, refund and profit-extraction paths
- promising but not retained directions: `cashOut` burn-before-transfer loss claim, `repayLoan` unauthorized burn/debt mismatch claim, pool-parameter validation concern, `extractProfit` interference scenario

## Cross-Agent Status
- main overlap in file/area attention: strongest overlap on `rebalance/LamboRebalanceOnUniwap.sol` and ETH/slippage/rebalance execution paths; both also focused on router/rebalance interaction points
- notable differences in attention: codex_1 emphasized system configuration assumptions (vETH backing type, integration addresses), while opencode_1 emphasized function-level execution hazards and accounting checks
- underexplored but suspicious files/functions if clearly supported by the logs: `LamboToken.sol` and `LamboFactory.sol` received comparatively less deep follow-up in this round relative to router/rebalance-focused analysis

## Retained Findings
- retained after merge were both from `codex_1`:  
  1. router/rebalance do not enforce native-backed `vETH`, enabling misconfiguration-driven functional DoS (`F-009`, low/medium)  
  2. `previewRebalance` uses raw pool balances and is donation-manipulable, degrading keeper decision quality and causing possible gas grief/reverts (`F-010`, low/medium)


Output only markdown.
