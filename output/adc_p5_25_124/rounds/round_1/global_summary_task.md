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
No global memory yet.

## Latest Round Summary
# Round 1 Summary

## Agent: codex_1
- files touched: `0xde46fcf6ab7559e4355b8ee3d7fba0f2730cddd8/Contract.sol`
- files revisited / highest-attention files: `0xde46fcf6ab7559e4355b8ee3d7fba0f2730cddd8/Contract.sol` was repeatedly inspected, including passes over externally callable functions and pool/accounting mutation sites
- main issue directions investigated: public reward-crediting via `calcStepIncome`, `withdraw()` payout/accounting branches, `joinGame()` and `activeParent()` reactivation behavior, hardcoded VIP privilege paths, insurance payout edge cases
- promising but not retained directions: broader scan of other public functions and arithmetic sites was performed, but no additional retained issue beyond the five merged findings

## Agent: opencode_1
- files touched: `0xde46fcf6ab7559e4355b8ee3d7fba0f2730cddd8/Contract.sol` and the round task file
- files revisited / highest-attention files: `0xde46fcf6ab7559e4355b8ee3d7fba0f2730cddd8/Contract.sol`
- main issue directions investigated: basic scope confirmation and contract file loading
- promising but not retained directions: no concrete vulnerability direction was developed in the visible log

## Cross-Agent Status
- main overlap in file/area attention: both agents focused on the single in-scope Solidity file, `0xde46fcf6ab7559e4355b8ee3d7fba0f2730cddd8/Contract.sol`
- notable differences in attention: `codex_1` performed the substantive review and concentrated on `withdraw()`, `joinGame()`/`activeParent()`, VIP initialization, and `calcStepIncome`; `opencode_1` remained at file-discovery/read stage
- underexplored but suspicious files/functions if clearly supported by the logs: no additional file hotspot exists in scope; within `Contract.sol`, functions surfaced in the callable-function scan but not retained this round include `settlementStatic()` and `setAmbFlag()`

## Retained Findings
- Public `calcStepIncome` can be called directly to fabricate withdrawable rewards and drain round liquidity.
- `withdraw()` has a final-branch accounting bug that zeroes the round withdraw balance before payment, orphaning current-round claims.
- `joinGame()`/`activeParent()` can revive inactive accounts with prior-round earning state in the current round.
- Hardcoded VIP addresses receive massively elevated reward caps relative to ordinary users.
- The final insurance claimant can lose the residual payout because the insurance pool is zeroed before the payout amount is assigned.


Output only markdown.
