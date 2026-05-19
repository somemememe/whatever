# Global Audit Memory

## Scope Touched
- `coinbase.sol` — audit attention centers on the `execute()` settlement path, attacker-supplied `actions` payload construction, and nearby slippage/output parameter handling
- `execute()` flow via the settler — repeatedly relevant because it appears to expose external-call capability under the settler’s approvals/authority model

## Issue Directions Seen
- Attacker-controlled `actions` may provide an arbitrary external-call primitive through the settler
- Approval/authority boundaries around token pulls and settlement execution are a core theft direction, especially where the settler may act using its own standing approvals
- Weak or zeroed slippage/output constraints are a recurring secondary direction because they may allow side-effectful execution without meaningful swap settlement

## Useful Context
- So far the audit has remained tightly concentrated on `coinbase.sol`, with little evidence yet from other files or flows
- The strongest durable pattern is not generic swap mispricing but unsafe flexibility in the settlement/action-execution mechanism
- A retained critical finding already exists on abusive caller-controlled action execution through `execute()`; adjacent observations mainly reinforce that same trust-boundary theme
