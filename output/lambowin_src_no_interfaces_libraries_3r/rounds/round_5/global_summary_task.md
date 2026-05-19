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
- Persistent core scope: `VirtualToken.sol`, `LamboFactory.sol`, `LamboVEthRouter.sol`, `rebalance/LamboRebalanceOnUniwap.sol`; supporting but lower-yield repeats: `LamboToken.sol`, `Utils/LaunchPadUtils.sol`.
- Most cross-round signal concentrates at router/rebalance and their interaction with virtual debt/accounting paths; this round again heavily revisited `LamboVEthRouter.sol`, `rebalance/LamboRebalanceOnUniwap.sol`, `VirtualToken.sol`.
- Factory launch creation remains a confirmed critical hotspot (pair/LP setup fragility, including deterministic-address pre-creation DoS).
- Rebalance execution remains a confirmed hotspot (weak execution-side output/slippage guarantees).

## Issue Directions Seen
- Durable core direction: accounting-consistency gaps between virtual mint/burn/debt state and real transferable/native backing assumptions.
- Launch-flow fragility remains recurring: init/pool creation sequencing and deterministic-address assumptions can brick or DoS launches.
- Router/rebalance market-execution mismatch remains recurring: quote/preview signals vs executable outcomes, transfer/backing assumptions, and MEV/slippage exposure.
- Newly retained as durable direction: configuration trust around `vETH` backing type is weakly enforced, allowing misconfiguration-driven functional DoS at router/rebalance boundaries.
- Newly retained as durable direction: `previewRebalance` dependence on raw pool balances is donation-manipulable, degrading keeper signal quality and creating gas-grief/revert-prone behavior.
- Frequently explored but lower-retention themes: generic deadline/pause hygiene, callback/profit-accounting edges, approval/trust framing, broad owner-centralization, and most upgradeable/initializer hypotheses.

## Useful Context
- Highest-retention outcomes continue to come from end-to-end call-path validation across factory -> router -> rebalance -> virtual token accounting, not checklist-only scans.
- Cross-agent convergence is strongest at router/rebalance execution boundaries; broad sweeps in those files generate many hypotheses but only a few durable findings.
- Round-level attention is currently skewed toward router/rebalance, while `LamboFactory.sol` and `LamboToken.sol` saw comparatively less deep follow-up despite prior factory criticality.


## Latest Round Summary
# Round 5 Summary

## Agent: codex_1
- files touched: `LamboFactory.sol`, `LamboToken.sol`, `LamboVEthRouter.sol`, `Utils/LaunchPadUtils.sol`, `VirtualToken.sol`, `rebalance/LamboRebalanceOnUniwap.sol` (plus supporting reads in `libraries/UniswapV2Library.sol` and interfaces)
- files revisited / highest-attention files: `LamboFactory.sol`, `LamboVEthRouter.sol`, `VirtualToken.sol`, `rebalance/LamboRebalanceOnUniwap.sol`
- main issue directions investigated: router-fee enforceability vs direct pair trading, rebalance direction encoding, Uniswap V2 `feeTo` effects on “burned” LP assumptions
- promising but not retained directions: stuck native ETH in `receive()` flows, implementation-contract `initialize()` exposure in `LamboToken`, `previewRebalance` revert-on-equal-balances behavior

## Agent: opencode_1
- files touched: all in-scope contracts (`LamboFactory.sol`, `LamboToken.sol`, `LamboVEthRouter.sol`, `Utils/LaunchPadUtils.sol`, `VirtualToken.sol`, `rebalance/LamboRebalanceOnUniwap.sol`) plus prior round/global summaries
- files revisited / highest-attention files: `rebalance/LamboRebalanceOnUniwap.sol`, `VirtualToken.sol`, `LamboVEthRouter.sol` (via targeted greps: `directionMask`, `minReturn`, `MAX_LOAN_PER_BLOCK`, `onlyValidFactory`)
- main issue directions investigated: rebalance mask/amountOut/minReturn handling, VirtualToken debt/loan/cashOut edge cases, quote/manipulation/front-run style concerns
- promising but not retained directions: multiple hypotheses were proposed but not kept after merge (including rebalance slippage/minReturn and several VirtualToken edge-case claims)

## Cross-Agent Status
- main overlap in file/area attention: rebalance logic in `rebalance/LamboRebalanceOnUniwap.sol`, especially direction selection/encoding (retained as shared support for F-012)
- notable differences in attention: codex_1 produced retained economic/design findings spanning factory-router-token interactions; opencode_1 emphasized broader candidate issues in rebalance/VirtualToken but did not add additional retained findings beyond corroborating rebalance direction risk
- underexplored but suspicious files/functions if clearly supported by the logs: `LamboToken.sol` had limited retained impact despite review; native-ETH handling paths were flagged but not retained this round

## Retained Findings
- F-011: router fee model is bypassable because traders can interact directly with the public launch Uniswap V2 pair instead of router fee paths.
- F-012: rebalance swap direction is derived from WETH identity rather than actual pool token ordering, creating deployment-dependent direction failures.
- F-013: Uniswap V2 `feeTo` protocol-fee minting can recreate LP claims despite the intended burned-liquidity model.


Output only markdown.
