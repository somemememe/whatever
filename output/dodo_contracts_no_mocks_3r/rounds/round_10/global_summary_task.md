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
- `GatewaySend.sol`: central hotspot across agents/rounds for cross-chain settlement entry (`onCall`), swap execution, and routing/amount handling.
- `GatewayTransferNative.sol`: repeated focus on native withdrawal/refund paths (`withdrawToNativeChain`) and fee/value accounting edges.
- `GatewayCrossChain.sol`: consistently reviewed as part of gateway execution flow and cross-chain state transitions.
- `libraries/SwapDataHelperLib.sol`, `libraries/TransferHelper.sol`, `libraries/AccountEncoder.sol`: supporting paths repeatedly checked for swap input handling, transfer accounting, and message/account decoding assumptions.

## Issue Directions Seen
- Interface/ABI conformance at gateway callback boundaries (notably `onCall`) is a high-signal direction; one confirmed mismatch already caused full settlement-path revert behavior.
- Amount accounting mismatches remain a recurring theme: nominal vs actual received tokens, pre-fee vs post-fee amounts, and `amount` vs `msg.value` semantics.
- Cross-chain routing consistency checks (`dstChainId`/asset pairing) and execution-path invariants are repeatedly probed as potential logic-risk areas.
- Failure/refund behavior around swaps/deposits and downstream calls is a persistent investigation direction, often adjacent to reentrancy/refund ordering concerns.

## Useful Context
- Multi-agent overlap is strongest in `GatewaySend.sol` + `GatewayTransferNative.sol` around `onCall`, swap/mix-swap, and withdrawal/refund execution paths.
- Broad candidate issue generation has occurred, but most did not survive merge; durable signal so far is concentrated in callback compatibility and amount/fee-path correctness.
- Retained confirmed issue: `GatewaySend.onCall` return type incompatibility (`bytes4` vs expected dynamic `bytes`) can make authenticated gateway deliveries revert, effectively bricking that settlement path.


## Latest Round Summary
# Round 10 Summary

## Agent: codex_1
- files touched: `GatewayTransferNative.sol`, `GatewaySend.sol`, `GatewayCrossChain.sol`, plus broad symbol/structure scans across `libraries/*.sol` and `interfaces/*.sol`
- files revisited / highest-attention files: highest attention on `GatewayTransferNative.sol` (multiple focused slices), then `GatewaySend.sol` and `GatewayCrossChain.sol`
- main issue directions investigated: receive-side amount/accounting vs actual received funds, native-fee handling on ETH-sentinel paths, payout transfer semantics (ERC20 return handling, ETH `transfer` gas stipend), WZETA unwrap behavior in same-token vs swap branches
- promising but not retained directions: proposed `F-027` to `F-030` were not retained in round merge; only `F-031` survived

## Agent: opencode_1
- files touched: `GatewayCrossChain.sol`, `GatewaySend.sol`, `GatewayTransferNative.sol`, `libraries/SwapDataHelperLib.sol`, `libraries/AccountEncoder.sol`, plus prior round summary file
- files revisited / highest-attention files: repeated reads of `GatewaySend.sol` and `GatewayTransferNative.sol`; targeted grep sweeps for approvals, withdraw paths, deadlines, message decoding, sender usage
- main issue directions investigated: `onCall` token movement, `externalId`/timestamp entropy, `withdraw` access control, refund event correctness
- promising but not retained directions: submitted findings mapped to already-known or unretained themes in this round; no additional retained finding attributed from this agent

## Cross-Agent Status
- main overlap in file/area attention: strong overlap on `GatewaySend.sol` and `GatewayTransferNative.sol`, especially callback payout and withdrawal/refund-related paths
- notable differences in attention: `codex_1` did deeper path-sensitive analysis around same-token/swap branching and asset-type handling; `opencode_1` emphasized pattern-grep and broader hypothesis generation (timestamp/access-control/event issues)
- underexplored but suspicious files/functions if clearly supported by the logs: interface and utility surfaces (`interfaces/*`, `UniswapV2Library.sol`, `BytesHelperLib.sol`, `TransferHelper.sol`) received comparatively lighter direct scrutiny this round

## Retained Findings
- `F-031` (Low, high confidence): in `GatewayTransferNative.onCall`, same-token WZETA flow skips unwrap logic and sends wrapped WZETA instead of native ZETA, which can break recipient expectations and strand funds for contracts that cannot handle/recover ERC20s.


Output only markdown.
