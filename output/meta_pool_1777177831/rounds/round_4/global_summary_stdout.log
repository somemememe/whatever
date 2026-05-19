# Global Audit Memory

## Scope Touched
- OpenZeppelin upgradeability stack: `ERC1967Upgrade`, `ERC1967Proxy`, `TransparentUpgradeableProxy`, `BeaconProxy`, `UpgradeableBeacon`, `Proxy`, `ProxyAdmin` — recurring focus on upgrade execution, admin/fallback dispatch, beacon control, and delegatecall reachability
- Supporting utilities/interfaces: `Address`, `StorageSlot`, `Ownable`, `IERC1967`, `IERC1822`, `IBeacon`, `Context` — secondary context for slot correctness, ownership/admin invariants, low-level calls, and interface compatibility assumptions
- Deployment/setup paths: payable proxy constructors, optional initializer payloads, and payable admin-facing upgrade hooks — repeatedly relevant to skipped initialization, upgrade-time call behavior, and possible stranded ETH

## Issue Directions Seen
- Upgrade and initialization sequencing across ERC-1967 / transparent / beacon flows remains the dominant audit direction, especially where setup delegatecalls can alter authority or state assumptions
- Transparent proxy admin vs non-admin dispatch is the clearest recurring hotspot: proxy-layer admin gating does not by itself rule out implementation-defined upgrade reachability for non-admin callers
- ERC-1967 slot integrity and control invariants remain a steady review axis, covering implementation/admin/beacon slot handling, upgrade helper behavior, and the ownership surface around `ProxyAdmin` and beacons
- Beacon-based upgrade paths remain a monitored direction, centered on ownership, implementation resolution, validation, and execution ordering during proxy calls
- Delegatecall entrypoints and upgrade hooks continue to be probed for cross-pattern interactions, including transparent/UUPS-style overlap and implementation-triggered upgrade paths
- Payable deployment and admin behavior remains a concrete concern: constructor ETH, empty initializer data, and payable upgrade/admin flows can create subtle fund-handling or setup-state edge cases

## Useful Context
- Cross-round attention remains concentrated on upstream OpenZeppelin proxy mechanics rather than protocol-specific business logic
- `TransparentUpgradeableProxy.sol` and `ERC1967Upgrade.sol` are the most repeatedly scrutinized files, with `BeaconProxy.sol`, `UpgradeableBeacon.sol`, `ProxyAdmin.sol`, `ERC1967Proxy.sol`, and `Proxy.sol` as the main follow-up surfaces
- Support files such as `Address`, `StorageSlot`, `IERC1967`, `IERC1822`, `IBeacon`, `Ownable`, and `Context` consistently serve as background context rather than primary finding sources
- Recent review reinforced proxy dispatch, slot handling, beacon validation, payable admin behavior, and delegatecall flow as central investigated surfaces, but did not add retained findings
- Audit history still reflects a single consistent review thread with no meaningful cross-agent divergence; lighter-attention interfaces/utilities have stayed contextual rather than emerging into durable hotspots
