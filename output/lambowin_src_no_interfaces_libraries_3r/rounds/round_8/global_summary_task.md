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
- Persistent core scope: `VirtualToken.sol`, `LamboFactory.sol`, `LamboVEthRouter.sol`, `rebalance/LamboRebalanceOnUniwap.sol`; recurring secondary scope: `LamboToken.sol`, `Utils/LaunchPadUtils.sol`, plus Uniswap V2 interface/library dependencies.
- Highest sustained attention remains on router/rebalance execution boundaries and virtual accounting state transitions, especially `LamboVEthRouter.sol`, `rebalance/LamboRebalanceOnUniwap.sol`, and `VirtualToken.sol`.
- Factory launch/pool setup and pair/LP lifecycle assumptions remain a recurring structural dependency surface.

## Issue Directions Seen
- Durable accounting-control direction: virtual debt mint/burn authority and repayment semantics can drift from intended borrower/factory isolation (including cross-factory authorization overreach).
- Durable boundary-control direction: router redemption/whitelist intent can be bypassed or weakened through composable pair routing (`quoteToken/vETH` paths into `cashOut`-style flows).
- Durable execution-context direction: rebalance/preview correctness depends on quote-path call semantics (`view`/`STATICCALL` compatibility), not just arithmetic.
- Durable execution direction: rebalance safety is sensitive to swap-direction/token-order derivation and descriptor/mask forwarding assumptions.
- Durable liquidity-model direction: LP-burn finality assumptions are unstable under Uniswap V2 `feeTo` protocol-fee mint behavior.
- Durable launch-flow direction: init/pool-creation sequencing and deterministic-address assumptions can create launch fragility/DoS conditions.
- Durable funds-handling direction: native ETH can accumulate in router/rebalancer surfaces that accept ETH but lack explicit recovery paths.

## Useful Context
- Highest-yield work remains end-to-end call-path validation across factory -> router -> rebalance -> virtual token, rather than isolated single-function review.
- Cross-agent convergence is strongest at router/rebalance and factory-authorization boundaries; retained issues have come from boundary/invariant violations, not generic parameter-risk hypotheses.
- Repeated low-confidence signals still cluster around rebalance descriptor/mask plumbing and router fee/sell-path governance knobs, but durability has depended on concrete exploitability evidence.


## Latest Round Summary
# Round 8 Summary

## Agent: codex_1
- files touched  
  `LamboFactory.sol`, `LamboToken.sol`, `LamboVEthRouter.sol`, `VirtualToken.sol`, `Utils/LaunchPadUtils.sol`, `rebalance/LamboRebalanceOnUniwap.sol`; also read multiple `interfaces/**` files for integration context.
- files revisited / highest-attention files  
  `VirtualToken.sol`, `rebalance/LamboRebalanceOnUniwap.sol`, `LamboVEthRouter.sol`.
- main issue directions investigated  
  factory-authorized debt minting/repayment boundaries in `VirtualToken`; rebalance sizing controls vs preview target; router fee behavior and token-handling edge cases; implementation initialization surface for clone pattern.
- promising but not retained directions  
  `F-020` (implementation initialize), `F-021` (router ERC20 rescue absence), `F-022` (100% fee setting effects) were proposed by this agent but not retained after merge.

## Agent: opencode_1
- files touched  
  Read all in-scope contracts: `LamboFactory.sol`, `LamboToken.sol`, `LamboVEthRouter.sol`, `VirtualToken.sol`, `Utils/LaunchPadUtils.sol`, `rebalance/LamboRebalanceOnUniwap.sol`; also read prior round and global summaries.
- files revisited / highest-attention files  
  Broad pass across all in-scope files; no specific hotspot singled out beyond known-issue validation.
- main issue directions investigated  
  attempted to find distinct new root causes vs known findings; re-checked router sell/buy paths, virtual token debt logic, rebalance execution/preview assumptions, and factory launch flow.
- promising but not retained directions  
  none advanced; agent concluded no new distinct findings and returned `[]`.

## Cross-Agent Status
- main overlap in file/area attention  
  Strong overlap on `VirtualToken.sol`, `LamboVEthRouter.sol`, and `rebalance/LamboRebalanceOnUniwap.sol`, with focus on debt accounting and rebalance execution controls.
- notable differences in attention  
  `codex_1` performed deeper hypothesis testing and produced candidate new findings; `opencode_1` mostly validated against existing-known findings and did not escalate new issues.
- underexplored but suspicious files/functions if clearly supported by the logs  
  No additional underexplored hotspot is clearly supported by these logs beyond already-discussed debt-loan and rebalance-size surfaces.

## Retained Findings
- `F-018` retained: `VirtualToken.takeLoan` can let authorized factories mint debt into existing pairs, creating unsynced balance-as-input conditions that can extract quote reserves.
- `F-019` retained: permissionless rebalance accepts arbitrary caller `amountIn` not bounded to preview-derived target, enabling oversized but still passable rebalances with pool-quality harm.


Output only markdown.
