# Global Audit Memory

## Scope Touched
- `onchain_auto/0x76ea342bc038d665e8a116392c82552d2605eda1/Contract.sol` — Uniswap V2-style pair contract; repeated attention on `initialize`, `_update`, `mint`, `burn`, `swap`, `skim`, and `sync`, with the strongest issue directions around reserve/live-balance trust, oracle state propagation, and permit-domain caching

## Issue Directions Seen
- Compatibility and accounting fragility when token balances drift outside standard AMM assumptions, especially reserve desynchronization versus live balances
- Permissionless extraction of surplus balances through `skim` when balance-increasing or otherwise non-standard token behavior leaves excess assets in the pair
- Malicious or non-standard `balanceOf` behavior as a core trust boundary: forged balances can satisfy swap input checks, distort reserve updates, and drain the honest-side asset
- Oracle/TWAP integrity risk when manipulated balances are written into reserves and then into cumulative pricing state
- Permit replay risk tied to cached `DOMAIN_SEPARATOR` behavior across chain-id changes or forks
- Initialization and `mint`/`burn` safety were investigated repeatedly, but the durable pattern remains accounting/trust assumptions rather than privileged reconfiguration or simple flow theft

## Useful Context
- Audit activity remains tightly concentrated on a single pair contract rather than a wider protocol surface
- The most persistent cross-round theme is unsafe reliance on token-reported balances, not privileged-role misuse
- Retained concerns consistently involve non-standard token mechanics causing either extractable surplus, swap path breakage/DoS, LP loss realization, or oracle corruption when reserves are reconciled
- `swap`, `_update`, `skim`, and downstream reserve/oracle writes form the main cross-round risk cluster
