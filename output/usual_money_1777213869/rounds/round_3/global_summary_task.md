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
- `FlawVerifier.sol` — dominant audit surface across rounds; attention stays centered on `executeOnOpportunity()`, `_tryCycle()`, and the swap/probe/liquidation execution chain, with issue directions around treasury custody, open execution, missing run-level profit enforcement, and unsafe external interaction
- `FlawVerifier.sol` selector/probing helpers, approval paths, and low-level call sites — repeatedly important because broad approvals and value-bearing external calls are composed in one flow, including concern about fixed endpoint assumptions
- `FlawVerifier.sol` hard-coded token/router endpoints — now a durable scope item because chain-specific constant addresses can misroute value or break assumptions off mainnet
- `Counter.sol` — lightly reviewed auxiliary scope; earlier unrestricted state-write direction did not persist, and coverage remains shallow relative to `FlawVerifier.sol`

## Issue Directions Seen
- Treasury/value flow may be lost, trapped, or degraded because execution can move funds through multiple external steps without a clear end-to-end profitability invariant
- Main strategy execution appears exposed to overly broad triggering, keeping permissionless treasury-touching execution as a recurring direction
- Swap/liquidation paths continue to suggest extraction risk from weak output guarantees and balance-sensitive execution
- Broad approvals plus blind or weakly constrained low-level interactions remain a central side-effect/destructive-call direction
- Fixed mainnet address assumptions are now a retained direction: hard-coded endpoints create wrong-chain/value-sink risk when deployment environment differs from the assumed network

## Useful Context
- Cross-round signal is overwhelmingly concentrated in `FlawVerifier.sol`; absence of comparable findings elsewhere should not be read as broad safety
- The most durable pattern is unsafe composition inside one strategy path: approvals, probing, swaps, and liquidation all occur while the contract is actively custodying value
- A new durable observation is that correctness depends not just on individual substeps succeeding, but on the whole opportunity cycle ending profitably; success of helpers alone is not a sufficient safety signal
- `Counter.sol` remains low-coverage and low-signal; it has been touched, but durable audit memory is still driven by the main execution contract


## Latest Round Summary
# Round 3 Summary

## Agent: codex
- files touched: `FlawVerifier.sol`, `Counter.sol`; detailed review effort stayed concentrated on `FlawVerifier.sol`
- files revisited / highest-attention files: `FlawVerifier.sol` main execution and helper areas, especially `executeOnOpportunity()`, `_tryCycle()`, probe helpers, approval helpers, and balance/returndata safety wrappers; `Counter.sol` was only lightly checked
- main issue directions investigated: recursive reentrancy through untrusted target calls into a public entrypoint; persistent max approvals to `TARGET`; spoofable profit/balance signals via ETH/WETH injection and permissive `receive()`/`fallback()`; denial of service via oversized returndata in low-level helper wrappers
- promising but not retained directions: no additional non-retained directions were clearly logged beyond the final candidate findings produced

## Cross-Agent Status
- main overlap in file/area attention: only `codex` participated this round, with attention overwhelmingly centered on `FlawVerifier.sol`
- notable differences in attention: `Counter.sol` remained peripheral, while `FlawVerifier.sol` received repeated line-numbered review of execution, probing, approval, swap, and helper-call paths
- underexplored but suspicious files/functions if clearly supported by the logs: `Counter.sol` remained low-attention; within `FlawVerifier.sol`, low-level helper surfaces around `_safeBalanceOf()`, `_safeApprove()`, `_attempt()`, and target-call probing remained active suspicion points in the logs

## Retained Findings
- None.


Output only markdown.
