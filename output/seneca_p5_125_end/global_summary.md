# Global Audit Memory

## Scope Touched
- `contracts/Chamber2.sol`: dominant review target across rounds; risk concentration around batched operations, solvency enforcement, oracle/rate usage, liquidation, interest accounting, and clone initialization
- `contracts/interfaces/IMasterContract.sol`: touched as supporting context for clone/master-contract initialization patterns
- `contracts/Constants.sol`: supporting context for liquidation and pricing assumptions around `Chamber2`
- `contracts/libraries/BoringRebase.sol`: supporting context for accounting/rebase behavior linked to debt and liquidation paths
- `contracts/interfaces/IBentoBoxV1.sol`: supporting context for vault interactions feeding solvency/liquidation behavior

## Issue Directions Seen
- Deferred solvency checks in batched `performOperations()` remain a core direction, especially where unsupported operation sequences can clear or bypass intended validation
- Oracle initialization/update and cached exchange-rate handling are a recurring focus, including stale, zero, or otherwise unsafe rates being accepted by solvency and liquidation logic
- Liquidation safety is a persistent direction, mainly where pricing, exchange-rate freshness, and accounting assumptions interact
- Interest accrual and `changeInterestRate()` semantics are a standing accounting direction, especially around retroactive effects on existing debt
- Clone deployment/initialization trust boundaries remain a lower-confidence but durable direction due to one-shot `init()` capture concerns

## Useful Context
- Audit attention is heavily concentrated in `Chamber2.sol`; supporting files have mainly served to explain its accounting, vault, and liquidation behavior rather than emerging as independent issue hubs
- Cross-agent overlap centered on oracle/rate handling and downstream solvency/liquidation effects, suggesting those mechanics are structurally important to the protocol
- Reentrancy, slippage, gas-DoS, liquidation array mismatch, blacklist bypass, and zero-amount dust theories were explored but did not persist as durable directions from this round
