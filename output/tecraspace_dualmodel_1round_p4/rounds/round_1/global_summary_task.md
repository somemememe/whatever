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
- files touched: `0xe38b72d6595fd3885d1d2f770aa23e94757f91a1/Contract.sol`
- files revisited / highest-attention files: repeated line-by-line passes over `0xe38b72d6595fd3885d1d2f770aa23e94757f91a1/Contract.sol`, especially state-changing functions, upgrade/deprecation handling, and allowance/balance writes
- main issue directions investigated: `burnFrom` allowance handling; upgrade/deprecation behavior; legacy `_balances` / `_allowances` writes through non-canonical paths; overall state-write and privilege surfaces
- promising but not retained directions: invalid `upgrade()` target bricking canonical ERC20 operations was reported by this agent but not retained after merge

## Agent: opencode_1
- files touched: `0xe38b72d6595fd3885d1d2f770aa23e94757f91a1/Contract.sol`
- files revisited / highest-attention files: only the in-scope `Contract.sol` is visible in the log
- main issue directions investigated: owner recovery via `acquire()`; blacklist coverage in `burn` / bulk transfer paths; upgrade redirection risk; pause coverage gaps; `permit` domain separator behavior; missing role-management events
- promising but not retained directions: reported but not retained themes included `acquire()` fund-drainability, blacklist/pause-consistency issues, invalid/malicious upgrade redirection, permit fork behavior, and missing admin events

## Cross-Agent Status
- main overlap in file/area attention: both agents focused entirely on `0xe38b72d6595fd3885d1d2f770aa23e94757f91a1/Contract.sol`, with shared attention on upgrade/deprecation behavior
- notable differences in attention: `codex_1` concentrated on exploitability of token state transitions (`burnFrom`, hidden legacy ledger), while `opencode_1` spread attention across admin powers, blacklist/pause enforcement, and operational/integration issues
- underexplored but suspicious files/functions if clearly supported by the logs: no additional files were explored; within `Contract.sol`, `permit`, `acquire`, and role-management / pause-related paths were raised by only one agent and were not retained

## Retained Findings
- `burnFrom` uses an inverted allowance lookup/update, enabling arbitrary third parties to self-create the checked allowance entry and burn another holder’s tokens
- the upgrade path leaves legacy storage live through non-deprecated write functions, creating a split-brain token state where standard ERC20 views redirect to the upgraded contract while old-ledger balances/allowances can still be mutated


Output only markdown.
