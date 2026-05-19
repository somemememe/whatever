# Global Audit Memory

## Scope Touched
- `FlawVerifier.sol` — dominant audit surface; `executeOnOpportunity()` is the central path for execution control, external-call sequencing, unwrap behavior, swap-path assumptions, and end-of-run profit gating
- `FlawVerifier.sol` custody/accounting paths — repeated focus on trapped or misinterpreted value, especially native ETH/WETH already held by the contract and how balances are reused across runs
- `FlawVerifier.sol` balance/profit checks — persistent hotspot for prefunded/donated balance contamination and the retained “ratcheting baseline” effect from trapped ETH profits across successive executions
- `FlawVerifier.sol` external dependency segments — recurring review area for fixed-counterparty trust, chain/environment assumptions, and missing validation that expected external/token-side state changes actually occurred before later logic continues
- `Counter.sol` — secondary but repeatedly revisited for unrestricted public mutability / integrity concerns; still lightly explored relative to `FlawVerifier.sol`

## Issue Directions Seen
- Value custody and accounting is the clearest cross-round theme, spanning trapped funds, stray ERC20/native assets, and profit inference from raw balances
- Denial-of-service or griefing via balance-dependent execution/profit checks remains a durable direction
- Profit-gating in `FlawVerifier.sol` is susceptible to balance contamination, including pre-existing assets being mistaken for fresh profit and historical profits skewing future eligibility
- Retained direction: trapped ETH profits can accumulate into a rising internal baseline, eventually causing otherwise-profitable future runs to fail
- Permissionless triggering/front-running of the hardcoded execution path remains a standing direction tied to loss of operator timing control
- Hardcoded external-address trust and chain/environment coupling keeps resurfacing as a suspicious but low-confidence direction
- External-interaction correctness in `FlawVerifier.sol` remains a recurring hypothesis, especially whether downstream swap/profit logic assumes a prior token-side state change without explicitly validating it
- `Counter.sol` public mutability/authorization concerns recur intermittently as low-severity integrity hypotheses, still without deep confirmation

## Useful Context
- Cross-round attention remains overwhelmingly concentrated in `FlawVerifier.sol`, especially `executeOnOpportunity()` and the unwrap-plus-final-balance-check path
- The most stable risk pattern is reliance on balance deltas as a proxy for successful execution, both within a single transaction and across repeated runs
- Review threads increasingly connect custody, profitability checks, and long-lived contract state: retained profits are part of future execution conditions rather than neutral bookkeeping
- Hardcoded dependency and external-call analysis has been more useful for hypothesis generation than for producing retained bugs so far
- `Counter.sol` still has only light coverage, so lack of retained findings there reflects limited attention more than strong assurance
