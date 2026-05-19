# Global Audit Memory

## Scope Touched
- `onchain_auto/0x7aa375f1fe5e04e18a6b02b4294cfd57ca9f53ba/contracts/Comptroller.sol` — central surface for policy-hook behavior, market membership/accounting, and liquidity-loop scaling risks
- `onchain_auto/0x7aa375f1fe5e04e18a6b02b4294cfd57ca9f53ba/contracts/CToken.sol` — paired closely with Comptroller hook call paths for redeem, transfer, repay, liquidation, and flash-loan-adjacent review
- `onchain_auto/0x7aa375f1fe5e04e18a6b02b4294cfd57ca9f53ba/contracts/ComptrollerStorage.sol` — relevant for `accountAssets`, `maxAssets`, and collateral-cap/state-layout context
- `onchain_auto/0x7aa375f1fe5e04e18a6b02b4294cfd57ca9f53ba/contracts/Unitroller.sol` / `CTokenInterfaces.sol` — touched for proxy-storage and interface context, but not yet tied to retained issues
- `onchain_auto/0x3d5bc3c8d13dcb8bf317092d84783c2697ae9258/contracts/CToken.sol` and sibling branch — mapped lightly; materially less explored than the `0x7aa...` branch

## Issue Directions Seen
- Protocol-breaking policy-hook reverts in `Comptroller.sol` are a confirmed direction, affecting redeem / exit / transfer flows and separately repay / liquidation-repay flows
- Market-membership growth versus liquidity-check iteration is a confirmed direction: `accountAssets` can effectively grow without a practical cap, pushing gas-sensitive liquidity and liquidation paths toward DoS conditions
- Collateral-cap accounting and market-entry ordering is a live lower-confidence direction, especially where collateral registration can happen before membership checks and rely on downstream hook idempotence
- Flash-loan logic in `CToken.sol` and proxy/upgradability surfaces around `Unitroller.sol` were examined enough to remain notable context, but have not yet produced retained cross-round issues

## Useful Context
- Cross-round attention is concentrated far more on the `0x7aa...` deployment than the parallel `0x3d5...` branch
- `Comptroller.sol` is the recurring highest-value file; most durable issue directions converge on its authorization hooks, market-entry bookkeeping, and liquidity calculations
- Redeem/transfer and repay/liquidation paths repeatedly matter because they couple `CToken` user actions to Comptroller policy decisions
- Some explored edge cases, such as `redeemVerify` redundancy, were investigated but not durable enough to keep as memory compared with the broader hook and accounting patterns
