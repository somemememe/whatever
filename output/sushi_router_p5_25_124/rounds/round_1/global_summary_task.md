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
- files touched: `contracts/RouteProcessor2.sol`, `contracts/InputStream.sol`
- files revisited / highest-attention files: `contracts/RouteProcessor2.sol` dominated attention, with `InputStream.sol` used to confirm route parsing/control flow
- main issue directions investigated: arbitrary V3/CL pool callback trust, router-owned ERC20/Bento/native inventory spending via route commands, unwrap-native payout behavior, Bento bridge/accounting edge cases
- promising but not retained directions: zero-amount Bento surplus capture at `bentoBridge` was explored and sanity-checked, but did not survive merge as a retained finding

## Agent: opencode_1
- files touched: `contracts/RouteProcessor2.sol`, `contracts/InputStream.sol`, `interfaces/IBentoBoxMinimal.sol`, `interfaces/IPool.sol`, `interfaces/IUniswapV2Pair.sol`, `interfaces/IWETH.sol`
- files revisited / highest-attention files: `contracts/RouteProcessor2.sol` was the clear focal point; `InputStream.sol` and Bento/pool interfaces were supporting reads
- main issue directions investigated: slippage/deadline coverage, fake or unvalidated pool usage, Bento recipient misuse, callback/reentrancy concerns, route/input validation weaknesses
- promising but not retained directions: generic slippage/deadline/recipient-validation findings and several broader validation concerns were raised, but were not retained after merge; the fake-pool direction only persisted in narrowed form through the V3/CL callback-theft finding

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `contracts/RouteProcessor2.sol`, especially untrusted route execution and external pool interactions; both converged on the retained V3/CL callback exploit path
- notable differences in attention: `codex_1` focused on concrete fund-drain primitives tied to router-held assets and accounting gaps, while `opencode_1` spent more effort on generalized slippage, deadline, and validation themes and read more supporting interfaces
- underexplored but suspicious files/functions if clearly supported by the logs: outside `RouteProcessor2.sol` and `InputStream.sol`, the wider scope appears lightly covered this round; most attention stayed on router execution paths rather than the rest of the in-scope files

## Retained Findings
- arbitrary V3/CL-style pools can abuse callback trust to pull approved user funds or router-held ERC20s
- public route commands can sweep router-held ETH, ERC20, and Bento inventory because final input accounting does not prove caller-funded consumption
- native unwrap sends the router’s full ETH balance rather than only the intended unwrap amount
- `processUserERC20` is not bound to the declared `tokenIn`, enabling malicious routes to pull other approved caller assets or Bento shares


Output only markdown.
