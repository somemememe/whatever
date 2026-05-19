# Global Audit Memory

## Scope Touched
- `FlawVerifier.sol` — dominant audit surface; `executeOnOpportunity()` remains the main execution-control / custody / trade-safety hotspot
- `FlawVerifier.sol` target-driven dependency path — repeated attention on trusting `TARGET` for runtime addresses and other external values used during execution
- `FlawVerifier.sol` approval / seed-deposit path (`_prepareNonZeroAaveInput()`) — recurring review area for persistent AAVE allowance exposure to `TARGET`
- `FlawVerifier.sol` withdrawal / profit-accounting path — revisited around how balances and execution outcomes are validated after swaps / external calls
- `Counter.sol` — lightly reviewed only; permissionless mutability / state-integrity concerns remain secondary and low-signal versus verifier logic

## Issue Directions Seen
- Asset custody / recoverability weaknesses in prefunded verifier flows, especially stranded ETH or residual token balances without a recovery path
- Open execution surfaces where arbitrary callers can trigger treasury-backed or prefunded strategy execution at unintended times
- Economically unsafe swap configuration, especially zero-minimum-output trades that invite slippage, sandwiching, and MEV extraction
- Execution fragility from brittle timing assumptions around AMM interactions, making transactions easier to fail or censor under ordinary delay
- External dependency trust-boundary risk, especially `FlawVerifier.sol` relying on `TARGET`-supplied or hardcoded counterparties / addresses for critical runtime behavior
- Broad approval-scope risk, particularly persistent or unlimited approvals granted to external targets beyond the immediate intended action
- Chain-environment mismatch and mainnet-specific assumption risk remain a recurring investigation thread, though less durable than the broader trust-boundary concern

## Useful Context
- Audit attention remains heavily concentrated in `FlawVerifier.sol`; cross-round risk still clusters around execution design and integration boundaries rather than arithmetic bugs
- The most durable pattern is the combination of prefunding, permissionless triggering, external target trust, swap brittleness, and broad approvals in one flow
- Recent review sharpened focus on target-controlled reads, approval setup, withdrawal handling, and profit-check logic as the verifier’s main pressure points
- `Counter.sol` remains comparatively underexplored and lower priority; it has not developed into a major cross-round issue area
- Several round-specific ideas were investigated but not retained; the stable memory centers on custody, execution safety, target trust, approvals, and environment assumptions
