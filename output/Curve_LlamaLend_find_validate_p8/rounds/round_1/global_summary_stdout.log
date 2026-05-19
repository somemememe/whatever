# Global Audit Memory

## Scope Touched
- `Curve_LlamaLend.sol` — primary audit surface so far; attention centers on the exploit path around savings-vault collateral handling, collateral/borrow validation, and liquidation helper flow
- Savings-vault / `sDOLA` path — durable concern that the redeem then `DOLA_SAVINGS.stake(..., address(sDOLA))` sequence can distort effective collateral valuation
- Pool / LLAMMA interaction path — recurring focus for state-dependent pricing inputs used by borrow sizing, `min_collateral(...)`, and liquidation eligibility
- `LLAMMA_CRV_USD_AMM.exchange(...)` — especially zero-input state-refresh behavior remains a suspicious but unconfirmed hotspot

## Issue Directions Seen
- Share-price / assets-per-share manipulation of `sDOLA` collateral value through the savings-vault path
- Synchronous market-state manipulation, especially via flash-loaned pool / LLAMMA changes, influencing collateral requirements and borrow capacity
- Same-transaction liquidation enablement caused by manipulable market state rather than an independently durable liquidation-only bug
- General dependence on externally mutable pricing/state during validation and liquidation-critical checks

## Useful Context
- Audit attention is still concentrated in a single contract and one exploit-critical flow rather than broad code coverage
- The strongest cross-cutting pattern is that collateral valuation, borrow checks, and liquidation logic appear tightly coupled to transient state that may be attacker-steerable within one transaction
- Same-tx liquidation was explored separately at first, but the more durable framing is as a downstream consequence of broader state/pricing manipulation
- Zero-amount LLAMMA exchange behavior is worth remembering as unresolved context, even though it was not retained as a standalone finding
