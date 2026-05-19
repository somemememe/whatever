# Global Audit Memory

## Scope Touched
- `onchain_auto/0x4e34dd25dbd367b1bf82e1b5527dbbe799fad0d0/contracts/pool.sol` — overwhelmingly dominant audit surface; repeated attention on initialization/control, share-conversion helpers, debt/share accounting, solvency checks, and liquidation mechanics
- Core pool flows: `init`, `lend`, `redeem` / `redeemUnderlying`, `borrow` / `repay`, `liquidateInternal`, `liquidateMulti` — main state-transition paths where accounting and threshold mismatches surface
- Share/accounting helpers: `calculateShare`, `getShareByValue` — recurring hotspot for rounding, value-conversion, and share burn/mint inconsistencies
- In-scope utility libraries (`ReentrancyGuard`, `SafeERC20`, `Address`, `SafeMath`, `Counters`, `IERC20`) — mapped across rounds but still largely peripheral relative to `pool.sol`

## Issue Directions Seen
- Privileged setup risk around initialization and control assumptions remains a standing direction
- Redemption/collateral-withdraw checks may use pre-transfer or otherwise stale balances, weakening post-action health enforcement
- Interest accrual freshness versus share minting is a recurring economic dilution/value-capture direction, especially on `lend`
- Borrow-limit, health-factor, and liquidation-threshold formulas appear misaligned across paths, creating solvency and liquidation eligibility drift
- Floor-rounded share/debt math is a broad recurring pattern: borrowers, redeemers, and liquidators may receive more value than the shares burned or debt assigned
- Liquidation logic shows multiple promising accounting faults, including collateral-share underburn and multi-asset netting/cancellation behavior
- First-use or zero-position debt-share initialization is a known direction because it can strand bad debt in edge positions

## Useful Context
- Cross-round attention is still concentrated almost entirely in `pool.sol`; helper math and economic accounting dominate over library-level bugs
- The most durable theme is not isolated branch bugs but repeated inconsistency between asset value, share value, and debt value across mint, burn, borrow, redeem, and liquidation flows
- Solvency analysis is most useful when `borrow`, `redeem`, and liquidation paths are considered together rather than independently
- Rounding behavior appears material, not cosmetic: repeated floor conversions create extractable edge cases across several flows
- Batch liquidation deserves separate attention from single-position liquidation because its cross-token interactions introduce distinct netting behavior beyond ordinary threshold checks
