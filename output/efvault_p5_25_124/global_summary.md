# Global Audit Memory

## Scope Touched
- `onchain_auto/.../contracts/core/Vault.sol`: main audit hotspot; repeated attention on deposit/withdraw share accounting, prefunded-asset interactions, and whitelist enforcement boundaries
- `contracts/interfaces/IController.sol`, `contracts/interfaces/IWhitelist.sol`: relevant mainly for how vault access control and whitelist checks are wired into `Vault.sol`
- `contracts/utils/TransferHelper.sol`: supporting transfer path reviewed in relation to vault asset-flow assumptions
- secondary proxy/UUPS test area (`contracts/test/Proxiable.sol`, OZ `UUPSUpgradeable.sol`): briefly examined as an upgrade-authorization direction, but not an enduring issue area so far
- hashed `onchain_auto/...` layout: source-location resolution itself has been a recurring setup hurdle across agents

## Issue Directions Seen
- Vault share-accounting edge cases are the dominant direction, especially rounding, zero-share mint/burn outcomes, and balance-based accounting mismatches
- Prefunded or externally shifted token balances versus accounted deposits is a live pattern around vault minting logic
- Whitelist/access-control coverage around direct user interaction paths is a meaningful recurring direction
- Upgradeability takeover/auth-path concerns were probed in a secondary package, but have not persisted as a retained cross-round direction

## Useful Context
- Audit attention has concentrated much more on the vault package than on any other component
- Early effort can be consumed by resolving the real contract path inside hashed `onchain_auto` directories before substantive review starts
- Retained findings to date are vault-centric; no durable retained issue has emerged from the proxy/UUPS test package
