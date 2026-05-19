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
- `FlawVerifier.sol` — persistent audit center; repeated focus on `executeOnOpportunity()`, liquidation/swap execution, pool lifecycle hooks (`startPool`/`endPool`), `_sweepBounties()`, `_tryStartEnd()`, and final balance/profit checks
- `FlawVerifier` recovery/liquidation path — now repeatedly implicated not just in accounting and slippage concerns, but in executability fragility from dust/small-balance states and gas-heavy sweep behavior
- `Counter.sol` — only lightly examined across rounds; mostly background context with low durable signal

## Issue Directions Seen
- Value-capture and accounting behavior in `FlawVerifier.sol` remain the strongest recurring direction, especially whether profit realization can be stranded, mis-accounted, or distorted by execution-path assumptions
- Profit gating in `executeOnOpportunity()` is an established cross-round direction: fixed minimum gain thresholds can reject genuinely profitable but smaller recoveries, and profit validation around ETH vs token/WETH balances remains a recurring accounting hotspot
- Recovery-path executability is a durable direction alongside pure accounting risk: `_sweepBounties()`/`executeOnOpportunity()` can become impractical or revert due to gas-heavy brute-force sweeping and brittle liquidation assumptions
- Dust or tiny-balance conditions in liquidation are now a retained denial-of-service direction: externally introduced minimal token balances can make later liquidation steps revert and stall future opportunity execution
- Liquidation and swap execution remain a strong economic-risk direction due to limited effective slippage protection and MEV/front-run exposure
- Permissionless opportunity execution and lifecycle triggering continue to look like a possible griefing or value-extraction surface, including same-transaction start/end behavior and attacker-controlled parameterization reaching pool calls
- Bundled sweep/helper flows remain a recurring source of loop, silent-call-failure, and gas-amplification risk, though some low-level call-handling concerns reviewed so far have not been retained

## Useful Context
- Cross-round signal remains concentrated overwhelmingly in `FlawVerifier.sol`; review outside it is still thin
- Durable concerns are primarily economic, accounting, and execution-flow weaknesses rather than classic privileged-access bugs
- The most repeatedly examined hotspot is the lifecycle/sweep/profit-realization complex around `executeOnOpportunity()`, `_sweepBounties()`, `_tryStartEnd()`, liquidation, and final balance checks
- Sweep design carries retained audit weight both as a helper-path concern and as a realistic denial-of-service vector against the intended recovery transaction
- Tiny donated balances can matter materially in this codebase because recovery execution assumes certain liquidation preconditions rather than tolerating dust gracefully
- `Counter.sol` remains underexplored and low-signal relative to the main contract


## Latest Round Summary
# Round 6 Summary

## Agent: codex
- files touched: `FlawVerifier.sol`, `Counter.sol`
- files revisited / highest-attention files: `FlawVerifier.sol` received essentially all line-level attention; `Counter.sol` was inspected but not a focus
- main issue directions investigated: permissionless `executeOnOpportunity()` timing/griefing exposure; profit-check accounting around preloaded WETH/ERC20 balances; `startPool`/`endPool` sequencing when `startPool` fails; USDC/USDT transfer-block / blacklist DoS during liquidation
- promising but not retained directions: public one-shot sweep timing issue (`F-006` in agent output) and unconditional `endPool` after failed `startPool` (`F-008`) were explored but not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: only `codex` appears in this round's logs, with attention concentrated on `FlawVerifier.sol` execution flow, liquidation, and profit gating
- notable differences in attention: no cross-agent divergence is visible from the provided logs; `Counter.sol` received only cursory inspection versus deep review of `FlawVerifier.sol`
- underexplored but suspicious files/functions if clearly supported by the logs: `Counter.sol` remains effectively uninteresting from this round's evidence; within `FlawVerifier.sol`, `_tryStartEnd()` and `executeOnOpportunity()` were the main hotspots, while the `startPool`/`endPool` failure-handling path was investigated but not retained

## Retained Findings
- `F-007`: retained as a medium-severity profit-accounting flaw where preloaded WETH/supported tokens can satisfy the ETH-denominated profit check without new recovery value
- `F-009`: retained as a medium-severity centralized-stablecoin DoS path where blacklisted or transfer-blocked USDC/USDT balances can cause future recovery executions to revert entirely


Output only markdown.
