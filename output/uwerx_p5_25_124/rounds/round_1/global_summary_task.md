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
- files touched: `0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol`
- files revisited / highest-attention files: `Contract.sol`, especially `transferFrom`, `_transfer`, `_burn`, `_spendAllowance`, and `setUniswapPoolAddress`
- main issue directions investigated: sell-path accounting when `to == uniswapPoolAddress`; allowance vs. extra burn interaction; exact-balance / exact-amount transfer behavior; mismatch between `Transfer` events and storage updates; owner retargeting of the special pool path
- promising but not retained directions: none clearly shown beyond the retained sell-path and owner-retargeting issues

## Agent: opencode_1
- files touched: `0x4306b12f8e824ce1fa9604bbd88f2ad4f0fe3c54/Contract.sol`
- files revisited / highest-attention files: `Contract.sol`, with focus on `setUniswapPoolAddress`, `setMarketingWallet`, and references to `uniswapPoolAddress` / `marketingWalletAddress`
- main issue directions investigated: owner-controlled pool address; owner-controlled marketing wallet; immediate admin changes without timelock; missing events for parameter changes; centralization around owner privileges
- promising but not retained directions: marketing wallet redirection as direct theft, no-timelock admin risk, missing admin-change events, and general owner centralization concerns

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `Contract.sol` and the owner-controlled `uniswapPoolAddress` logic
- notable differences in attention: `codex_1` traced token flow and accounting through `transferFrom` / `_transfer` / `_burn`; `opencode_1` focused more on admin controls and configurability (`setUniswapPoolAddress`, `setMarketingWallet`)
- underexplored but suspicious files/functions if clearly supported by the logs: `setMarketingWallet` was examined by `opencode_1` but did not produce a retained issue; most retained attention remained on the sell-path in `_transfer`

## Retained Findings
- Retained issues center on the special sell path for transfers to `uniswapPoolAddress`: it can burn beyond approved allowance, require more than `amount` from the sender and break exact-balance exits, and emit `Transfer` logs that do not match real balance changes.
- The round also retained that the owner can repoint this broken sell-path behavior to an arbitrary destination by changing `uniswapPoolAddress`.


Output only markdown.
