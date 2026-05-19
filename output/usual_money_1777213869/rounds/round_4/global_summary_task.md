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
- `FlawVerifier.sol` — dominant audit surface across rounds; focus remains on `executeOnOpportunity()`, `_tryCycle()`, and the composed probe/swap/liquidation path, with issue directions around treasury custody, open execution, missing run-level profit enforcement, and unsafe external interaction
- `FlawVerifier.sol` low-level helper and approval surfaces — `_attempt()`, `_safeBalanceOf()`, `_safeApprove()`, selector/probing helpers, and related returndata/balance wrappers repeatedly matter because they sit on value-bearing external calls, persistent approvals, and permissive call handling
- `FlawVerifier.sol` entrypoint and ETH-receipt behavior — public execution plus permissive `receive()`/`fallback()` now matters as part of balance/profit accounting and reentrant call-shape review
- `FlawVerifier.sol` hard-coded token/router endpoints — durable scope item because chain-specific constants can misroute value or break assumptions off mainnet
- `Counter.sol` — lightly reviewed auxiliary scope; remains low-signal and shallow compared with `FlawVerifier.sol`

## Issue Directions Seen
- Treasury/value flow may be lost, trapped, or degraded because execution moves funds through multiple external steps without a clear end-to-end profitability invariant
- Main strategy execution remains exposed to overly broad triggering, keeping permissionless treasury-touching execution as a recurring direction
- Swap/liquidation paths continue to suggest extraction risk from weak output guarantees and balance-sensitive execution
- Broad or persistent approvals plus blind or weakly constrained low-level interactions remain a central destructive-call / side-effect direction
- Balance and profit signals appear sensitive to external state injection or spoofing, especially where ETH/WETH balances and permissive receive paths can influence perceived success
- External target interaction keeps reentrancy and call-return handling in scope, including risk from untrusted callbacks and oversized returndata causing execution disruption
- Fixed mainnet address assumptions remain a retained direction: hard-coded endpoints create wrong-chain/value-sink risk when deployment environment differs from the assumed network

## Useful Context
- Cross-round signal is overwhelmingly concentrated in `FlawVerifier.sol`; absence of comparable findings elsewhere should not be read as broad safety
- The most durable pattern is unsafe composition inside one strategy path: approvals, probing, swaps, liquidation, and helper-wrapped external calls all occur while the contract is actively custodying value
- Correctness depends on the whole opportunity cycle ending profitably; success of individual helpers or subcalls is not a sufficient safety signal
- Helper-layer behavior matters almost as much as core strategy logic because accounting, approvals, returndata handling, and external-call safety are delegated into wrappers
- `Counter.sol` remains low-coverage and low-signal; durable audit memory is still driven by the main execution contract


## Latest Round Summary
# Round 4 Summary

## Agent: codex
- files touched
  - `FlawVerifier.sol`, `Counter.sol`
- files revisited / highest-attention files
  - `FlawVerifier.sol` received the clear majority of attention, with repeated reads of its full body and a focused revisit around the middle execution path (`_tryCycle` / liquidation / balance-check area)
- main issue directions investigated
  - profitability / success-condition handling around native balance changes and payable entrypoints
  - reentrancy exposure from external calls, token interactions, approvals, and callback-capable paths
  - unrestricted state mutation in the minimal `Counter.sol` contract
- promising but not retained directions
  - broader execution / approval / liquidation path review in `FlawVerifier.sol` was mapped, but no additional retained findings emerged beyond the candidate issues the agent output

## Cross-Agent Status
- main overlap in file/area attention
  - only one agent logged activity this round, so attention was concentrated on `FlawVerifier.sol`
- notable differences in attention
  - `Counter.sol` was checked briefly for simple access-control/state-integrity issues, while `FlawVerifier.sol` received detailed control-flow scrutiny
- underexplored but suspicious files/functions if clearly supported by the logs
  - `FlawVerifier.sol` helper call surfaces referenced in the output (`_attempt`, `_call0`, `_call1`, `_call2`, `receive`, `fallback`) were treated as risky interaction points, but the logs show limited full-function inspection outside the highlighted execution slice

## Retained Findings
- None retained from this round after merge.


Output only markdown.
