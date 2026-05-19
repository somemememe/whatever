# Global Audit Memory

## Scope Touched
- `contracts/token/BBTOKENv2.sol`: primary hotspot across rounds; registry-swappable mint authorization and supply-cap behavior dominate attention
- `contracts/utils/Registry.sol`: relevant supporting surface for minter authorization and failure/revert behavior, but less concretely developed than token logic
- upgradeable proxy initialization path (`ERC1967Proxy` deployment wiring): secondary area tied to possible initialization-capture risk if deployment leaves proxy uninitialized

## Issue Directions Seen
- missing access control around registry configuration enabling mint-authorization bypass and operational disruption
- advertised supply cap / `maxSupply` state not actually enforced during initialization or subsequent minting
- upgradeable initialization safety remains a recurring but lower-confidence direction, dependent on deployment procedure
- admin/configuration centralization and registry-dependency behavior surfaced repeatedly as supporting risk themes, though not all were retained as findings

## Useful Context
- cross-round analysis concentrated heavily on `BBTOKENv2.sol`; other files mostly mattered insofar as they influenced its minting and initialization behavior
- the registry is treated as the trust anchor for mint permissions, so registry mutability is the key bridge between configuration bugs and direct token inflation
- several softer observations repeated without maturing into retained findings: hardcoded/admin-controlled configuration quirks, metadata inconsistencies, and registry missing-key revert behavior
