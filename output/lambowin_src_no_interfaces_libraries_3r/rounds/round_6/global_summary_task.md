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
- Persistent core scope: `VirtualToken.sol`, `LamboFactory.sol`, `LamboVEthRouter.sol`, `rebalance/LamboRebalanceOnUniwap.sol`; recurring secondary scope: `LamboToken.sol`, `Utils/LaunchPadUtils.sol`; occasional support reads in Uniswap V2 library/interface paths.
- Cross-round signal remains strongest at router/rebalance plus virtual accounting integration, with repeated revisits to `LamboVEthRouter.sol`, `rebalance/LamboRebalanceOnUniwap.sol`, and `VirtualToken.sol`.
- Factory launch/pool setup assumptions continue to matter (including deterministic/pair-state fragility), and Uniswap V2 pair/LP mechanics are now a sustained dependency theme.

## Issue Directions Seen
- Durable core direction: accounting-consistency gaps between virtual debt/mint-burn state and real transferable/native backing assumptions.
- Durable market-structure direction: protocol fee capture assumptions at router level are bypassable when public pair trading paths remain open.
- Durable execution direction: rebalance correctness is sensitive to swap-direction derivation/token-order assumptions, with deployment-dependent failure modes.
- Durable liquidity-model direction: “burned LP = no LP claims” assumptions are unstable under Uniswap V2 `feeTo` protocol-fee mint behavior.
- Durable launch-flow direction: init/pool-creation sequencing and deterministic-address assumptions can brick or DoS launches.
- Retained but secondary: `previewRebalance` signal quality can be distorted by raw pool-balance donation effects (keeper-quality/gas-grief surface).

## Useful Context
- Highest-yield work remains end-to-end call-path validation across factory -> router -> rebalance -> virtual token accounting, not isolated checklist scans.
- Cross-agent convergence is strongest in router/rebalance boundaries; many hypotheses appear there, but only a small subset persists after adversarial merge.
- Rebalance and router continue to absorb most deep attention; factory/token areas periodically resurface with high-impact economic/design interactions when revisited.


## Latest Round Summary
# Round 6 Summary

## Agent: codex_1
- files touched: `LamboFactory.sol`, `LamboToken.sol`, `LamboVEthRouter.sol`, `VirtualToken.sol`, `Utils/LaunchPadUtils.sol`, `rebalance/LamboRebalanceOnUniwap.sol`, plus interface/library files for integration context
- files revisited / highest-attention files: `LamboVEthRouter.sol`, `VirtualToken.sol`, `rebalance/LamboRebalanceOnUniwap.sol`
- main issue directions investigated: router-mediated `vETH` redemption boundary (`sellQuote` + `cashOut`), native ETH handling/recovery gaps in router and rebalancer, implementation initialization surface in `LamboToken`, rebalance pool-descriptor masking
- promising but not retained directions: publicly initializable `LamboToken` implementation, low-confidence `directionMask`/descriptor-bit injection concern in rebalancer

## Agent: opencode_1
- files touched: `LamboFactory.sol`, `LamboToken.sol`, `LamboVEthRouter.sol`, `VirtualToken.sol`, `Utils/LaunchPadUtils.sol`, `rebalance/LamboRebalanceOnUniwap.sol`, and prior round/global summaries
- files revisited / highest-attention files: `rebalance/LamboRebalanceOnUniwap.sol`, `VirtualToken.sol`, `LamboVEthRouter.sol`
- main issue directions investigated: loan/debt semantics in `VirtualToken`, rebalance slippage/output enforcement, owner extraction surfaces, reserve/quote robustness, hardcoded external approval dependency
- promising but not retained directions: multiple hypotheses were proposed, but none from this agent were retained after merge for Round 6

## Cross-Agent Status
- main overlap in file/area attention: strong overlap on `LamboVEthRouter.sol`, `VirtualToken.sol`, and `rebalance/LamboRebalanceOnUniwap.sol`
- notable differences in attention: `codex_1` concentrated on router whitelist-boundary bypass and ETH recoverability; `opencode_1` emphasized broader accounting/slippage/governance-style hypotheses
- underexplored but suspicious files/functions if clearly supported by the logs: `rebalance` descriptor/mask handling (`directionMask` composition path) remains a logged but unretained low-confidence area; `LamboToken` implementation `initialize` path was investigated but not retained

## Retained Findings
- `F-014`: retained the router-as-whitelisted-redemption-adapter issue where arbitrary `quoteToken/vETH` pairs can route `vETH` into `cashOut`, weakening whitelist boundary intent
- `F-015`: retained native ETH stuck-funds issue for router and rebalancer due to `receive()` acceptance without native-ETH rescue/withdraw flow


Output only markdown.
