# Global Audit Memory

## Scope Touched
- `0x3d9819210a31b4961b30ef54be2aed79b9c9cd3b/Contract.sol`: legacy flattened Compound market logic; repeated attention on `mint` / `repayBorrow` / `liquidateBorrow` accounting, especially fee-on-transfer over-credit paths
- `0xbafe01ff935c7305907c33bf824352ee5979b526/contracts/CToken.sol`: core market money flows, transfer-in/out, borrow/redeem/liquidation paths; canonical reference for accounting and reentrancy review
- `Comptroller.sol`: central recurring hotspot for liquidity/account-membership logic, `accountAssets` growth, market controls, liquidation gating, and COMP accrual/remediation behavior
- `ComptrollerStorage.sol`: relevant for `maxAssets` and COMP distribution state backing `Comptroller` behaviors
- `Unitroller.sol`: upgrade / delegation surface noted, but only lightly explored relative to core flow files
- related interfaces / `CTokenInterfaces.sol` / `Exponential.sol`: supporting context for storage layout, math, and cross-contract flow tracing

## Issue Directions Seen
- Fee-on-transfer handling in legacy cToken-style flows is a strong recurring direction; durable concern is accounting based on requested amount rather than assets actually received
- `Comptroller` asset-membership growth and unenforced `maxAssets` indicate recurring gas-grief / liquidity-loop pressure around `accountAssets`
- COMP accrual repair paths remain a live direction; `fixBadAccruals` behavior suggests bookkeeping can diverge from what users can later claim
- Core borrow/redeem/liquidation flows and cross-market liquidity checks keep surfacing as the main economic-risk area
- Privileged control, oracle/model replacement, guardian controls, deprecation handling, and upgrade delegation were explored but have not yet produced retained issues
- Reentrancy around `doTransferOut` and stale cross-market state was investigated and remains background context, not a retained direction

## Useful Context
- Cross-round attention is concentrated on `Comptroller.sol` plus cToken market accounting paths; this is the audit’s main convergence zone
- The legacy flattened `Contract.sol` deserves separate scrutiny from canonical `CToken.sol` because retained accounting bugs were specific to the flattened implementation
- Governance / upgradeability surfaces have been reviewed more as trust-boundary context than as confirmed exploit paths
- Underexplored area with some signal: `Unitroller` fallback/delegate path received limited direct scrutiny compared with core market logic
