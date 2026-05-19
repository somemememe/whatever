# Global Audit Memory

## Scope Touched
- `onchain_auto/0x951d51baefb72319d9fbe941e1615938d89abfe2/Contract.sol` — dominant focus area; repeated attention on `OptionsExchange` trade helpers, oracle-priced safety/liquidation math, vault accounting/lifecycle, and exercise/redeem/payout paths
- Vault-selection and exercise flows — concern that fungible oToken exercise routing can target specific vaults and behave inconsistently across multi-vault ETH-underlying cases
- Uniswap buy/sell helper flows — recurring slippage exposure and ETH-funding-path concerns
- Oracle-dependent collateral/liquidation logic — repeated zero-price validity/freeze direction across safety checks, exercise, and liquidation
- Vault owner enumeration helpers — low-attention but repeatedly resurfacing fragility around `getVaultOwners()`

## Issue Directions Seen
- Oracle-price validity is a central direction, especially zero-price handling causing denial/freeze behavior in core flows
- Exchange helper paths repeatedly suggest weak execution protections: minimal slippage bounds, ETH sourced from contract balance, and approval/configuration risk surfaces
- Vault lifecycle logic remains promising: exerciser-controlled vault routing, fairness of vault selection for fungible positions, payout correctness, and redemption/exercise consistency
- ERC20 interaction safety is a recurring concern, especially unchecked transfer return values breaking accounting or claims
- Edge-case accounting around ETH underlying assets and multi-vault state splitting appears more fragile than standard ERC20 cases
- Admin/configuration and helper-level robustness issues recur, but have been secondary to pricing and vault-flow concerns

## Useful Context
- Cross-round attention is highly concentrated in a single contract rather than spread across the codebase
- The strongest repeated overlap is between oracle-dependent math and `OptionsExchange` helper behavior
- Vault semantics merit continued scrutiny because several distinct issue directions converge there: selection, exercise, liquidation, payout, and redemption
- `getVaultOwners()` has surfaced multiple times as suspicious but remains underexplored relative to the main retained themes
