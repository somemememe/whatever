# Round 6 Summary

## Agent: codex_1
- files touched: `GatewayCrossChain.sol`, `GatewayTransferNative.sol`, `GatewaySend.sol`
- files revisited / highest-attention files: `GatewayCrossChain.sol` and `GatewayTransferNative.sol` (multiple targeted reads around swap/withdraw/refund logic)
- main issue directions investigated: refund keying/callback behavior, swap output trust vs balance reality, Uniswap exact-output allowance lifecycle, ETH deposit overload amount handling, callback message-length edge cases
- promising but not retained directions: refund-slot collision/poisoning, swap return-value trust without balance-delta checks, callback length-guard issues, refund bookkeeping edge cases (`externalId == 0`, post-delete event fields)

## Agent: opencode_1
- files touched: `GatewaySend.sol`, `GatewayTransferNative.sol`, `GatewayCrossChain.sol`, `libraries/SwapDataHelperLib.sol`, `libraries/AccountEncoder.sol`, `libraries/BytesHelperLib.sol`, `libraries/TransferHelper.sol`, `libraries/UniswapV2Library.sol`, `interfaces/IDODORouteProxy.sol`
- files revisited / highest-attention files: the three gateway contracts, especially `GatewaySend.sol` and `GatewayTransferNative.sol`
- main issue directions investigated: callback return/decoding behavior, swap parameter/amount validation, slippage/approval handling, withdraw recipient validation, public withdraw surface, parser safety in swap-data decoding
- promising but not retained directions: multiple medium/low hypotheses across callback semantics, amount validation, and decoding robustness; overlap with retained allowance-residual DoS theme in exact-output Uniswap flow

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on gateway swap/withdraw paths, with direct overlap on exact-output Uniswap approval behavior in `GatewayCrossChain.sol` and `GatewayTransferNative.sol`
- notable differences in attention: `codex_1` was more line-focused on exploit paths in core flows; `opencode_1` scanned more broadly across libraries/interfaces and produced more speculative edge-case candidates
- underexplored but suspicious files/functions if clearly supported by the logs: callback/refund handling paths (`onRevert`/`onAbort`/`claimRefund`) drew repeated scrutiny but did not persist as retained findings this round

## Retained Findings
- `F-023` (Medium): exact-output Uniswap approval pattern can leave residual allowance and later DoS strict-approve tokens (`GatewayCrossChain.sol`, `GatewayTransferNative.sol`)
- `F-024` (Low): ETH `depositAndCall` overload in `GatewaySend.sol` checks `msg.value >= amount` but forwards full `msg.value`, enabling unintended over-bridging
