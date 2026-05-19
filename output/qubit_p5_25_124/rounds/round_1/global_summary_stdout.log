# Global Audit Memory

## Scope Touched
- `onchain_auto/0x20e5e35ba29dc3b540a1aee781d0814d5c77bce6/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol` — central focus for admin/fallback routing and whether non-admin upgrade-selector calls can reach implementation logic
- `onchain_auto/0x20e5e35ba29dc3b540a1aee781d0814d5c77bce6/@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol` — repeatedly reviewed as the implementation-side upgrade surface behind proxy deployments
- `onchain_auto/0x20e5e35ba29dc3b540a1aee781d0814d5c77bce6/@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol` — relevant for selector flow and storage-slot based upgrade behavior in mixed transparent/UUPS setups
- `onchain_auto/0x20e5e35ba29dc3b540a1aee781d0814d5c77bce6/contracts/test/Proxiable.sol` — highlighted as a simple UUPS-style contract with weak/empty pre-upgrade gating, mainly useful as a pattern reference
- `onchain_auto/0xcd2cd343cfbe284220677c78a08b1648bfa39865/Contract.sol` — live implementation target remained effectively uninspectable, leaving actual exposed upgrade selectors unverified

## Issue Directions Seen
- Mixed transparent-proxy plus UUPS implementation composition is the dominant issue direction, especially whether proxy-level admin separation can be bypassed by forwarding upgrade selectors to the implementation
- Recurrent attention on implementation-controlled upgrade authorization, including empty or weak hook-based gating around upgrade entrypoints
- Direct calls to implementation upgrade functions remain a recurring suspicion, but depend on the concrete implementation actually exposing reachable upgrade methods
- Selector-routing behavior between proxy fallback logic and implementation upgrade APIs is the key cross-file interaction surface

## Useful Context
- Cross-round attention clusters around upgradeability control surfaces rather than business logic
- The strongest retained theme is a possible upgrade path outside `ProxyAdmin` when a `TransparentUpgradeableProxy` fronts an implementation with compatible upgrade functions
- `Proxiable.sol` drew repeated scrutiny, but its unrestricted-upgrade pattern appears more like a supporting signal than a confirmed live exploit path
- Confidence is constrained by limited visibility into the deployed implementation source, so conclusions hinge on architectural interaction more than direct implementation confirmation
