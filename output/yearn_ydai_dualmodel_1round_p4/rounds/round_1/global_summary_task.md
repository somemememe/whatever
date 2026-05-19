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
- files touched: `onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol`
- files revisited / highest-attention files: `onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol` with focus on vault accounting, `deposit()`, `earn()`, `withdraw()`, and `getPricePerFullShare()`
- main issue directions investigated: share-minting/accounting manipulation via external balance inflation; permissionless `earn()` draining the on-hand withdrawal buffer; zero-supply handling in PPS calculation
- promising but not retained directions: none clearly visible beyond the findings that were retained after merge

## Agent: opencode_1
- files touched: `../../../output/yearn_ydai_dualmodel_1round_p4/rounds/round_1/agent_opencode_1/current_task.md`, `onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol`
- files revisited / highest-attention files: `onchain_auto/0xacd43e627e64355f1861cec6d3a6688b31a6f952/Contract.sol`
- main issue directions investigated: controller/governance misconfiguration risk, `harvest()` token sweep behavior, public `earn()` behavior, zero-division edge cases in vault math, and user-protection gaps around deposit/withdraw execution
- promising but not retained directions: `setController(address(0))` fund-lock claim, `harvest()` draining non-core ERC20s, extra division-by-zero edge cases in `withdraw()`/`deposit()`, and slippage/deadline style concerns

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on the single in-scope vault contract, especially `earn()` and `getPricePerFullShare()`, and both surfaced the public-`earn()` liquidity-buffer issue plus the empty-vault PPS revert
- notable differences in attention: `codex_1` focused more on core vault accounting/share issuance and identified the retained inflation attack; `opencode_1` spent more attention on controller/admin paths, `harvest()`, and broader edge-case/user-execution concerns
- underexplored but suspicious files/functions if clearly supported by the logs: no additional files exist in scope; within the contract, controller/admin surfaces such as `setController()`, `setMin()`, and `harvest()` received one-agent attention but were not retained in the merged findings

## Retained Findings
- retained issues from this round are: an empty-vault/share-inflation attack that can steal later deposits through zero- or dust-share minting, permissionless repeated `earn()` calls that can shrink the withdrawal buffer to near zero, and `getPricePerFullShare()` reverting when called before any shares exist


Output only markdown.
