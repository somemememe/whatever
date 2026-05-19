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
