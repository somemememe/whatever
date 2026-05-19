# Round 4 Summary

## Agent: codex_1
- files touched: `GatewayCrossChain.sol`, `GatewayTransferNative.sol`, `GatewaySend.sol` (plus targeted line extraction across these); attempted local Foundry repro in `/tmp/ReturnMismatch.t.sol`
- files revisited / highest-attention files: highest attention on `GatewayTransferNative.sol` and `GatewayCrossChain.sol`; revisited specific swap/withdraw sections multiple times
- main issue directions investigated: swap-output/token-binding across DODO swap and payout token usage; withdrawal path accounting checks around `amountInMax`; additional checks on fee handling, callback ABI return compatibility, unchecked ERC20 `transferFrom`, refund event emission
- promising but not retained directions: candidate findings on fee/gross-amount mismatch in `GatewayTransferNative.onCall`, callback return ABI mismatch in `GatewaySend.onCall`, unchecked inbound `transferFrom` in `GatewaySend`, and refund event field ordering were proposed but not retained after merge

## Agent: opencode_1
- files touched: broad read of in-scope Solidity set, including `GatewayCrossChain.sol`, `GatewaySend.sol`, `GatewayTransferNative.sol`, `libraries/*`, and `interfaces/*`; also read prior round summary
- files revisited / highest-attention files: primary attention on the three gateway contracts, with grep-driven pattern sweeps (swap params, auth modifiers, deadlines, refund deletion, approvals)
- main issue directions investigated: parameter validation around swap return limits/deadlines, nonce/time usage, access-control surfaces, amount checks, decode paths, reentrancy absence, and approval usage patterns
- promising but not retained directions: a deadline-enforcement hypothesis (shown in its partial output) was not retained

## Cross-Agent Status
- main overlap in file/area attention: both focused on gateway fund-flow logic, especially swap/withdraw pathways in `GatewayCrossChain.sol` and `GatewayTransferNative.sol`
- notable differences in attention: `codex_1` did deeper exploit-path validation with concrete line-level traces and attempted a behavior repro; `opencode_1` emphasized broad static pattern scanning across all contracts/libraries
- underexplored but suspicious files/functions if clearly supported by the logs: no clearly supported underexplored hotspot beyond already-scanned gateway callback/swap surfaces

## Retained Findings
- `F-018` (Critical): swap output token is not bound to the later payout/withdraw token, enabling reserve-drain via asset mismatch in cross-chain and native transfer flows
- `F-022` (Medium): post-swap sufficiency check uses `amountInMax` instead of actual input spent, causing avoidable withdrawal reverts and liveness degradation
