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
- Persistent core scope remains `VirtualToken.sol`, `LamboVEthRouter.sol`, and `rebalance/LamboRebalanceOnUniwap.sol`, with repeated focus on debt accounting, redemption/sell paths, and rebalance sizing/execution boundaries.
- Structural dependency scope continues to include `LamboFactory.sol` (launch + authorization wiring), `LamboToken.sol`, `Utils/LaunchPadUtils.sol`, and Uniswap V2 pair/router interfaces.
- Highest-value flow lens is still end-to-end: factory authorization -> virtual debt mint/repay state -> router cashout/swap routes -> rebalance interaction with pool reserves.

## Issue Directions Seen
- Debt-authority drift remains a durable direction: factory-authorized `VirtualToken` loan paths can break borrower/pair isolation, including minting debt into existing pairs and creating reserve-extractable balance/input desync conditions.
- Rebalance-control drift remains durable: permissionless rebalance paths can accept caller-chosen `amountIn` beyond preview-intended sizing, allowing oversized yet valid executions that degrade pool quality.
- Router boundary weakening remains recurring: whitelist/redemption intent can be bypassed or weakened via composable quoteToken/vETH routing into cashout-style flows.
- Execution-context correctness remains recurring: rebalance reliability depends on call semantics and swap-direction/token-order/descriptor assumptions, not only numeric formulas.
- Liquidity lifecycle assumptions remain recurring: LP-burn finality can be invalidated by Uniswap V2 protocol-fee mint behavior (`feeTo`).

## Useful Context
- Cross-round convergence is strongest on boundary/invariant failures (authorization, accounting-state sync, execution bounds) rather than isolated parameter tuning.
- Latest round reinforced existing hotspots and retained two durable roots (debt-into-pair desync and unbounded rebalance sizing), while other hypotheses did not hold up as distinct findings.
- Broad rescans have not surfaced a clearly new hotspot outside the established debt-loan and rebalance-size surfaces.


## Latest Round Summary
# Round 9 Summary

## Agent: codex_1
- files touched: `LamboFactory.sol`, `LamboToken.sol`, `LamboVEthRouter.sol`, `VirtualToken.sol`, `interfaces/IRouter.sol`, `interfaces/IFactory.sol`, `interfaces/ILaunchpad.sol`, `interfaces/IPoolFactory.sol`, plus full `.sol` file listing via `find`
- files revisited / highest-attention files: `LamboFactory.sol` and `VirtualToken.sol` (debt + transfer constraint path); broad scan of other in-scope files
- main issue directions investigated: launch-pair debt mechanics vs Uniswap V2 LP accounting; whether debt-locked vETH can break LP burn/withdrawal for externally minted LP; quick compile sanity check attempt (`forge build`) to validate suspicious patterns
- promising but not retained directions: compile/dependency/setup issues observed during `forge build` (missing libs/submodule lock failure), not retained as in-scope security findings

## Agent: opencode_1
- files touched: `LamboFactory.sol`, `LamboToken.sol`, `LamboVEthRouter.sol`, `VirtualToken.sol`, `Utils/LaunchPadUtils.sol`, `rebalance/LamboRebalanceOnUniwap.sol`, plus prior `round_8` and global summaries
- files revisited / highest-attention files: broad equal-pass read across all in-scope contracts; grep-driven checks around `amountIn/amountOut/minReturn` and `mint`
- main issue directions investigated: input/output guards, min-return enforcement patterns, mint-related surfaces, consistency against prior known findings
- promising but not retained directions: no distinct new issue confirmed; final output was empty (`[]`)

## Cross-Agent Status
- main overlap in file/area attention: both reviewed core in-scope contracts, especially factory/router/token surfaces and mint/liquidity flows
- notable differences in attention: `codex_1` drilled into debt-floor transfer invariants and LP burn behavior; `opencode_1` stayed broader with grep-led pattern checks and did not develop a concrete exploit path
- underexplored but suspicious files/functions if clearly supported by the logs: no additional clearly supported hotspot beyond the retained factory/virtual-token debt-transfer interaction

## Retained Findings
- `F-020` retained: launch-pair vETH debt locking can make externally minted LP shares effectively non-burnable when burn-time vETH transfer crosses the pair’s debt floor, creating withdrawal lock risk for public LP providers.


Output only markdown.
