# Global Audit Memory

## Scope Touched
- `contracts/BaseSilo.sol`: central accounting and state-transition surface; repeated attention on deposits, repayments, `depositFor`, liquidation flow, and share-token interactions
- `contracts/Silo.sol`: wrapper/entry flow around core silo actions; relevant where user-facing operations route into `BaseSilo`
- `contracts/lib/Solvency.sol`: key solvency gate; cross-asset/account iteration and dependency on external interest-model reads look like recurring fragility points
- `contracts/interfaces/IShareToken.sol`: share-token transferability matters because collateral ownership can diverge from debt-bearing accounts
- `contracts/interfaces/ISiloRepository.sol`: repository/config lookups influence synced-asset and interest-model behavior in solvency paths
- `contracts/lib/TokenHelper.sol`: touched around token transfer/accounting correctness, especially actual-receipt vs nominal-amount assumptions
- `contracts/utils/LiquidationReentrancyGuard.sol`: liquidation safety surface was inspected, but remained secondary to core accounting/sequencing concerns

## Issue Directions Seen
- Separation of collateral and liability through transferable share tokens / per-account solvency mismatch
- Nominal `_amount` accounting for deposit and repay paths instead of actual tokens received, especially for fee-on-transfer or non-standard tokens
- Public `depositFor` dusting as a griefing vector that alters victim borrowing eligibility
- Solvency-dependent flows susceptible to DoS when synced-asset interest/model lookups revert
- Liquidation sequencing remains a meaningful direction, including callback/redeposit behavior affecting effective penalty or state assumptions

## Useful Context
- Cross-round attention concentrated heavily on `BaseSilo.sol` with `Silo.sol` and `Solvency.sol` as the main supporting paths
- Strongest repeated pattern is mismatch between internal accounting assumptions and real token/state behavior at the edges of deposits, repayments, solvency, and liquidation
- Several helper/config/guard files were touched, but the durable audit signal so far comes from core accounting and solvency flow composition rather than isolated helper bugs
