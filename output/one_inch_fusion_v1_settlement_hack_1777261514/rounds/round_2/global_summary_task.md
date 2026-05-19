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
- `FlawVerifier.sol` — primary audit focus; settlement execution path, replay construction, and token-drain helpers concentrate the main risk surface
- `executeOnOpportunity` flow — recurring attention on externally supplied interaction bytes diverging from the signed order payload
- `_buildReplayOrder` / replay path — repeatedly tied to calldata-shaping and historical order reuse concerns
- `_drainSettlementToken` / settlement payout path — repeatedly tied to draining real settlement-held inventory through bad accounting or crafted assets
- `Counter.sol` — briefly reviewed for unrestricted mutation, but not a durable issue direction so far

## Issue Directions Seen
- Unsigned or insufficiently bound external interaction data being executed inside settlement flows
- Self-targeted settlement reentry enabling privilege or `allowedSender` style bypass during nested execution
- Unsafe parsing of dynamic calldata offsets/lengths causing calldata corruption, replay construction, or reuse of historical orders
- Token-accounting trust assumptions around maker assets, including fake ERC20 behavior leading to payout of real settlement balances

## Useful Context
- Cross-round attention is highly concentrated on `FlawVerifier.sol`; helper paths around replay building and settlement draining are the most repeatedly scrutinized areas
- The strongest themes cluster around compositional failures: signed-order intent vs. executed calldata, nested settlement execution, and settlement inventory accounting
- `Counter.sol` has appeared only as a low-confidence side path and is not currently part of the core accumulated risk picture


## Latest Round Summary
# Round 2 Summary

## Agent: codex
- files touched: `FlawVerifier.sol`, `Counter.sol`
- files revisited / highest-attention files: `FlawVerifier.sol` received nearly all detailed review; `Counter.sol` was only briefly checked
- main issue directions investigated: crafted settlement/replay calldata around `_tryReplayCalldataCorruption()`, resolver/callback handling via `NoopResolver`, and whether settlement drains token balances based on live `SETTLEMENT` inventory in `_drainSettlementToken()`
- promising but not retained directions: possible mismatch between signed maker and interaction-supplied payer/source, callback success being satisfiable by a no-op or no-code resolver target, and settlement spending omnibus contract balances rather than order-scoped accounting

## Cross-Agent Status
- main overlap in file/area attention: only one agent log is present; attention was concentrated on `FlawVerifier.sol` settlement/exploit helper paths
- notable differences in attention: none visible from the logs because this round shows only one agent
- underexplored but suspicious files/functions if clearly supported by the logs: `Counter.sol` remained effectively untouched; within `FlawVerifier.sol`, swap/conversion helpers and some referenced interfaces/constants were searched but not deeply analyzed compared with settlement replay and drain paths

## Retained Findings
- None retained from this round after merge.


Output only markdown.
