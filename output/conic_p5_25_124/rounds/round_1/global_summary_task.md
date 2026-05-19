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
- files touched: `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol`, `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol`
- files revisited / highest-attention files: `RewardManagerV2.sol`, `ConicEthPool.sol`
- main issue directions investigated: reward checkpoint/accounting behavior during zero-stake periods, CNC accounting after selling extra rewards, reward-selling mechanics, ETH-pool reentrancy exposure during Curve/Convex interactions, rebalancing reward incentive design
- promising but not retained directions: unsupported extra-reward sales with zero slippage protection, ETH omnipool callback/read-only reentrancy during Curve operations

## Agent: opencode_1
- files touched: `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ConicEthPool.sol`, `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/RewardManagerV2.sol`, `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/ERC20.sol`, `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/Ownable.sol`, `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/IController.sol`, `0xbb787d6243a8d450659e09ea6fd82f1c859691e9/LpToken.sol`, `0x635228edaead8a76b6ae1779bd7682043321943d/ConvexHandlerV3.sol`
- files revisited / highest-attention files: `ConicEthPool.sol`, `RewardManagerV2.sol`
- main issue directions investigated: reentrancy, public depeg / invalid-pid handling, delegatecall trust boundaries, unlimited approvals, fee / admin controls, withdrawal slippage and reward-claim race conditions
- promising but not retained directions: missing reentrancy guard framing, public depeg/Convex-pid invalidation paths, unlimited approval risk, owner-controlled threshold/fee concerns, generic pause/controller centralization themes

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `ConicEthPool.sol` and `RewardManagerV2.sol`, especially reward flow and pool execution paths
- notable differences in attention: `codex_1` focused on reward-accounting and incentive mechanics; `opencode_1` spread attention into access control, delegatecall, approvals, and supporting contracts such as `Ownable.sol`, `IController.sol`, `LpToken.sol`, and `ConvexHandlerV3.sol`
- underexplored but suspicious files/functions if clearly supported by the logs: the `ConvexHandlerV3.sol` to `RewardManagerV2.sol` extra-reward claim/sale handoff was less directly explored in the visible logs than the main pool/reward files, but a retained finding ultimately landed there

## Retained Findings
- retained after merge: zero-stake reward backlog can be captured by the next staker; CNC from sold extra rewards can be counted twice and overpromise pool liabilities; Convex extra rewards can be claimed to the pool while the reward manager sells only its own balances, leaving extras stranded; rebalancing rewards can be farmed with temporary capital because only deposits are rewarded


Output only markdown.
