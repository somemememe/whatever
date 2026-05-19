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
- files touched: `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol`, `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol`, `0x635228edaead8a76b6ae1779bd7682043321943d/ConvexHandlerV3.sol`
- files revisited / highest-attention files: `RewardManagerV2.sol` received the deepest line-by-line attention; `ConicEthPool.sol` and `ConvexHandlerV3.sol` were the main companion files for flow tracing
- main issue directions investigated: reward checkpoint/accounting behavior around zero stake, Convex reward-claim routing versus sale path, post-depeg weight rescaling and deposit target selection, CNC accounting after reward-token sales
- promising but not retained directions: none clearly visible beyond the retained set; the only extra visible work was numeric sanity-checking of the rounding/deposit-revert scenario before retaining it

## Agent: opencode_1
- files touched: `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol`, `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol`, `0x635228edaead8a76b6ae1779bd7682043321943d/ConvexHandlerV3.sol`, `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/IERC20.sol`, `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/LpToken.sol`, `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/IController.sol`, `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ScaledMath.sol`, `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/IConicPool.sol`, `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/Initializable.sol`
- files revisited / highest-attention files: `ConicEthPool.sol`, `RewardManagerV2.sol`, and `ConvexHandlerV3.sol`; also grepped access-control checks across the `0xbb...` tree
- main issue directions investigated: reentrancy/order-of-operations in pool entrypoints, handler trust and access control, swap/slippage validation, reward-claim race/accounting behavior, oracle dependence, approval surfaces
- promising but not retained directions: multiple candidate issues were proposed around reentrancy, delegatecall/approval trust assumptions, missing handler access control, swap validation, and oracle/slippage risk, but none were retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents centered on `RewardManagerV2.sol`, `ConicEthPool.sol`, and `ConvexHandlerV3.sol`, with emphasis on reward flows and pool state transitions
- notable differences in attention: `codex_1` focused on concrete reward-accounting and deposit-allocation bugs; `opencode_1` spent more attention on generic security surfaces such as reentrancy, access control, delegatecall, approvals, and oracle/slippage
- underexplored but suspicious files/functions if clearly supported by the logs: support-layer files like `ScaledMath.sol`, `Initializable.sol`, `LpToken.sol`, and interface/control scaffolding were only lightly touched relative to the main pool/reward contracts

## Retained Findings
- reward accounting in `RewardManagerV2.sol` produced two retained issues: zero-stake intervals can let the first later staker capture the entire uncheckpointed reward backlog, and standalone reward-token sale flows can double-credit CNC
- reward routing between `ConvexHandlerV3.sol` and `RewardManagerV2.sol` retained a high-severity issue where Convex extra rewards are claimed to the pool but the sale path only inspects `RewardManagerV2` balances, stranding those tokens
- `ConicEthPool.sol` retained a medium-severity availability issue where floor-rounded weight rescaling during rebalancing can leave no valid deposit target and cause deposits to revert


Output only markdown.
