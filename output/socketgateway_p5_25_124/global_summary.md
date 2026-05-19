# Global Audit Memory

## Scope Touched
- `SocketGateway.sol`: central focus across rounds; route execution, post-swap bridge entrypoints, `delegatecall` surface, `swapAndMultiBridge` liveness, and route-disable behavior are recurring issue areas
- `BridgeImplBase.sol`: common bridge execution layer repeatedly tied to gateway-held fund usage and caller-influenced downstream bridge behavior
- Bridge implementations around native/value forwarding: `NativeOptimism.sol`, `NativeOpStack.sol`, `NativeArbitrum.sol`, Hop bridge variants, `ZkSyncBridgeImpl.sol`; these repeatedly matter for caller-chosen targets/amounts and gateway ETH/token spending assumptions
- `CelerImpl.sol`: revisited from both architectural and flow-specific angles, including refund handling and approval/fund movement concerns
- Secondary architecture/control surfaces: `SocketGatewayDeployment.sol`, `Ownable.sol`, `FeesTakerController.sol`, `SwapImplBase.sol`, `OneInchImpl.sol`, `Stargate.sol`, `SocketDeployFactory.sol`; examined mainly for access control, approval persistence, and route/address mapping assumptions

## Issue Directions Seen
- Gateway-routed bridge execution can spend assets already held by the gateway when post-swap or native bridge entrypoints trust caller-supplied targets, spenders, or amounts
- Native bridge paths are a repeated source of value-accounting risk, especially where `msg.value` is not reconciled against bridged amount or where arbitrary native targets can be selected
- Composed swap-plus-bridge flows are a consistent risk area for token custody/forwarding mistakes, including post-swap token handling on specific bridges
- Route execution architecture keeps surfacing questions around generic `delegatecall` exposure, route-address resolution, and the practical ability to disable routes
- Approval authority and persistence remain a recurring review direction around swap/bridge helpers, even where no retained finding was confirmed
- Non-theft failure modes also matter in this codebase: loop/liveness bugs and miswired admin controls can create DOS or ineffective safety switches

## Useful Context
- Cross-round attention converges most strongly on `SocketGateway.sol` plus bridge execution mechanics; this is the main audit center of gravity
- Durable retained issues skew toward concrete bridge-specific fund-loss paths rather than broad architectural suspicions
- Underexplored but repeatedly suspicious support surfaces include `FeesTakerController.sol`, `Stargate.sol`, `OneInchImpl.sol`, and `SocketDeployFactory.sol`
- Built-in route handling has both execution-surface importance and operational-control importance, not just configuration significance
