# Global Audit Memory

## Scope Touched
- `onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CToken.sol` — primary focus; share math, mint/redeem flows, exchange-rate usage, transfer-in/out accounting
- `onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CErc20.sol` — core ERC20 market wrapper reviewed alongside `CToken.sol` for underlying movement and balance-delta behavior
- `onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CErc20Immutable.sol` — lightly touched; initialization/market wiring remains comparatively underexplored
- `onchain_auto/0x7fcb7dac61ee35b3d4a51117a7c58d53f0a8a670/contracts/CarefulMath.sol`, `InterestRateModel.sol`, `ComptrollerInterface.sol` — supporting surfaces noted for arithmetic behavior, rate dependence, and external policy-hook assumptions
- Broader `onchain_auto` Solidity scope — regex/path discovery happened across the tree, but substantive analysis concentrated on Compound-style cToken market flows

## Issue Directions Seen
- Share-math edge cases where floor rounding allows nonzero underlying movement with zero cToken mint/burn
- Exchange-rate sensitivity to raw underlying balance, especially when direct donations can inflate market accounting inputs
- Value redistribution toward incumbent holders when sub-threshold mint/redeem operations succeed without proportional share updates
- Balance-delta assumptions around `doTransferIn` / `doTransferOut`, including interest in unusual underlying token behavior
- Dependence on external comptroller/policy hooks as a recurring trust boundary, though not yet a retained issue

## Useful Context
- The strongest cross-round pattern is the interaction between exchange-rate inflation and missing nonzero-result checks in mint/redeem share calculations
- Retained findings already center on zero-mint `mint` and zero-burn `redeemUnderlying` behaviors in the cToken flow family
- `CToken.sol` and `CErc20.sol` are the clear high-signal files; other supporting contracts were mostly contextual rather than deeply reviewed
- Donation-driven exchange-rate inflation and nonstandard underlying-token effects were investigated as enabling context, but not retained standalone in the first round
- Path resolution consumed some effort early; actual contract analysis so far is concentrated in the Compound-derived market implementation rather than the wider repository
