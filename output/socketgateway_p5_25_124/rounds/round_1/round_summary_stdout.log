# Round 1 Summary

## Agent: codex_1
- files touched: `SocketGateway.sol`, `SocketGatewayDeployment.sol`, `BridgeImplBase.sol`, `Across.sol`, `Connext.sol`, `refuel.sol`, `NativeOptimism.sol`, `NativeOpStack.sol`, `NativeArbitrum.sol`, `HopImplL1.sol`, `HopImplL1V2.sol`, `HopImplL2.sol`, `HopImplL2V2.sol`, `ZkSyncBridgeImpl.sol`, `NativePolygon.sol`, `gnosisNativeImpl.sol`, `CelerImpl.sol`
- files revisited / highest-attention files: `SocketGateway.sol`, `SocketGatewayDeployment.sol`, `BridgeImplBase.sol`, `NativeOptimism.sol`, `NativeOpStack.sol`, `NativeArbitrum.sol`, Hop bridge implementations, `ZkSyncBridgeImpl.sol`
- main issue directions investigated: raw route execution into `bridgeAfterSwap`; caller-controlled bridge target / spender parameters on Optimism, Op Stack, Arbitrum, and Hop; native bridge paths spending gateway ETH without reconciling `msg.value`; ZkSync composed-flow token handling; `swapAndMultiBridge` liveness; route-disable behavior for reserved route IDs
- promising but not retained directions: none clearly visible beyond the retained set

## Agent: opencode_1
- files touched: `SocketGateway.sol`, `Ownable.sol`, `BridgeImplBase.sol`, `CelerImpl.sol`, `OneInchImpl.sol`, `FeesTakerController.sol`, `SwapImplBase.sol`, `SocketDeployFactory.sol`, `AnyswapV6.sol`, `Cctp.sol`, `ISocketRequest.sol`, `Stargate.sol`
- files revisited / highest-attention files: `SocketGateway.sol` was read multiple times; secondary attention on `CelerImpl.sol`, `FeesTakerController.sol`, `Stargate.sol`, `OneInchImpl.sol`
- main issue directions investigated: generic delegatecall exposure in gateway route/swap/controller execution; hardcoded route-address mapping suspicion in `addressAt`; controller access control; approval persistence / approval authority; refund handling in Celer; swap slippage and zero-address validation
- promising but not retained directions: suspicion that many route IDs map to one hardcoded address; generic delegatecall-as-arbitrary-code-execution claims; unrestricted `FeesTakerController` and `refundCelerUser` concerns; lingering Stargate approvals; swap slippage / admin rescue centralization themes

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `SocketGateway.sol` and route execution mechanics; both also looked at `BridgeImplBase.sol` and `CelerImpl.sol`
- notable differences in attention: `codex_1` went broad across bridge implementations and retained concrete fund-loss / DOS issues; `opencode_1` stayed narrower and emphasized gateway/controller architecture, approvals, and admin-style risk themes
- underexplored but suspicious files/functions if clearly supported by the logs: `FeesTakerController.sol`, `Stargate.sol`, `OneInchImpl.sol`, and `SocketDeployFactory.sol` received attention from `opencode_1` but produced no retained findings this round

## Retained Findings
- retained issues centered on gateway-routed bridge execution spending assets already held by the gateway, especially via unrestricted post-swap entrypoints and native paths that trust caller-controlled amounts or targets
- concrete high-severity bridge-specific problems were retained for Optimism / Op Stack / Arbitrum target selection, Hop caller-chosen native targets, and ZkSync composed-flow token handling
- two non-theft issues were also retained: `swapAndMultiBridge` is DOSed by a non-incrementing loop, and built-in routes below ID `385` cannot actually be disabled
