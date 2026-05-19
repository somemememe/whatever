# Round 9 Summary

## Agent: codex_1
- files touched: `GatewayCrossChain.sol`, `GatewaySend.sol`, `GatewayTransferNative.sol` (plus broad `.sol` enumeration; referenced `SwapDataHelperLib.sol` in findings)
- files revisited / highest-attention files: `GatewayTransferNative.sol` and `GatewaySend.sol` (multiple targeted line inspections around `onCall`, `_doMixSwap`, and `withdrawToNativeChain`)
- main issue directions investigated: pre-fee vs post-fee amount handling, nominal-vs-actual token transfer accounting, `dstChainId`/`targetZRC20` consistency, native fee bypass via `amount` vs `msg.value`
- promising but not retained directions: proposed `F-026`/`F-027`/`F-028`/`F-029` set from this agent were not retained in merged round output

## Agent: opencode_1
- files touched: `GatewayCrossChain.sol`, `GatewaySend.sol`, `GatewayTransferNative.sol`, `libraries/AccountEncoder.sol`, `libraries/SwapDataHelperLib.sol`, `libraries/TransferHelper.sol` (also read prior round/global summaries)
- files revisited / highest-attention files: the three gateway contracts, especially `GatewaySend.sol` and `GatewayTransferNative.sol`
- main issue directions investigated: swap/deposit failure handling, `onCall` token amount trust, refund/reentrancy behavior, fee logic, access control, deadline/routing checks, message decoding bounds, missing events
- promising but not retained directions: many candidates (`F-026` to `F-035`) were proposed, but none were retained after merge

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `GatewaySend.sol`, `GatewayTransferNative.sol`, and cross-chain execution/settlement paths (`onCall`, swaps, withdraw/refund flow)
- notable differences in attention: `codex_1` focused on concrete amount/fee path mechanics and chain-routing consistency; `opencode_1` cast a wider net including eventing, deadline, and generic reentrancy themes
- underexplored but suspicious files/functions if clearly supported by the logs: callback interface conformance at `GatewaySend.onCall` vs gateway `Callable` expectations appears underexplored in agent runs and surfaced only in retained merge output

## Retained Findings
- retained after merge: **F-026 (High)**, an ABI return-type incompatibility where `GatewaySend.onCall` returns `bytes4` while ZetaChain `Callable.onCall` expects dynamic `bytes`, causing authenticated gateway deliveries to revert and effectively brick that settlement path.
