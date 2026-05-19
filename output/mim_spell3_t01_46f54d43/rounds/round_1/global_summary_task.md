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
- `cauldrons/CauldronV4.sol` — primary focus area; recurring concern around exchange-rate/oracle handling, solvency checks, borrowing, withdrawal, and liquidation behavior
- `cauldrons/PrivilegedCauldronV4.sol` — secondary focus on privileged debt/accounting paths, including borrow-position adjustments
- `cauldrons/PrivilegedCheckpointCauldronV4.sol` — checkpoint-token hook interactions around collateral operations and liquidation liveness
- `interfaces/*.sol` — reviewed mainly to understand surrounding call surface and assumptions
- `FlawVerifier.sol` — used as supporting exploit/context harness rather than a core issue source

## Issue Directions Seen
- Exchange-rate initialization and `updateExchangeRate()` behavior are a central audit direction, especially zero-rate and oracle-failure edge cases
- Cached/stale oracle values influencing solvency-sensitive actions recur as a promising class, affecting borrow, withdraw, and liquidation paths
- Liquidation and solvency enforcement can degrade when oracle outputs are invalid or stale, with debt checks collapsing or becoming bypass-prone in edge conditions
- Privileged cauldron accounting flows remain a watch area, though some specific leads were investigated without being retained
- Checkpoint-token hook side effects form a separate liveness/DoS direction for collateral adjustments and liquidations

## Useful Context
- Attention has been concentrated heavily in the cauldron contracts, with `CauldronV4` receiving the most line-by-line scrutiny so far
- Retained findings to date cluster into two broad themes: oracle/rate fragility in `CauldronV4` and hook-induced operational breakage in `PrivilegedCheckpointCauldronV4`
- Some reviewed items were contextual only and should not be overweighted in future rounds, particularly `FlawVerifier.sol`
- The audit signal so far favors durable protocol-state and liveness failures over one-off implementation nits


## Latest Round Summary
# Round 1 Summary

## Agent: codex
- files touched: `cauldrons/CauldronV4.sol`, `cauldrons/PrivilegedCauldronV4.sol`, `cauldrons/PrivilegedCheckpointCauldronV4.sol`, `interfaces/IOracle.sol`, `interfaces/IBentoBoxV1.sol`, `interfaces/IStrategy.sol`, `interfaces/ISwapperV2.sol`, `interfaces/ICheckpointToken.sol`, `FlawVerifier.sol`
- files revisited / highest-attention files: `cauldrons/CauldronV4.sol` received the most line-by-line review; `PrivilegedCauldronV4.sol` and `PrivilegedCheckpointCauldronV4.sol` were checked as nearby extensions; `FlawVerifier.sol` was searched for issue themes and scenario hints
- main issue directions investigated: oracle update/precision handling, solvency checks, liquidation edge cases and bad-debt cleanup, privileged debt-accounting helpers, checkpoint-token hook behavior, and repay skim semantics
- promising but not retained directions: owner-driven forced debt via `PrivilegedCauldronV4.addBorrowPosition()` and the `repay(..., skim=true)` source-of-funds behavior were flagged in the agent output but were not retained after merge

## Cross-Agent Status
- main overlap in file/area attention: only one agent logged this round; attention centered on `cauldrons/CauldronV4.sol`, especially oracle, solvency, borrow, and liquidation paths
- notable differences in attention: no cross-agent differences available this round
- underexplored but suspicious files/functions if clearly supported by the logs: `FlawVerifier.sol` and the broader interface set were only used as context; direct implementation scrutiny was concentrated in the cauldron contracts

## Retained Findings
- retained issues cluster around `CauldronV4` risk checks and liquidation correctness: zero-rate acceptance, stale-rate reuse on oracle failure, residual debt becoming unliquidatable after collateral exhaustion, and oracle-decimal mismatches
- one retained issue is isolated to `PrivilegedCheckpointCauldronV4`, where unconditional checkpoint-token hooks can revert and block collateral operations or liquidation
- overall retained finding set emphasizes oracle/input validation weaknesses plus liquidation-path failure modes rather than the privileged-helper and skim-repay theories raised in the raw agent output


Output only markdown.
