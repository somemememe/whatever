# Global Audit Memory

## Scope Touched
- `src/Laundromat.sol` — core focus across the audit so far; attention centers on the deposit-driven round lifecycle and the `withdrawStart` / `withdrawStep` / `withdrawFinal` withdrawal path
- `deposit()` round-filling logic — recurring hotspot tied to whether rounds can be advanced or saturated without commensurate value
- withdrawal state machine (`withdrawStart`, `withdrawStep`, `withdrawFinal`) — relevant because payout completion appears coupled to round-fill assumptions

## Issue Directions Seen
- Economic/state-accounting mismatch where repeated low- or zero-cost deposits may count toward filling a round
- Exploitability at the boundary between partially filled rounds and withdrawal completion
- Round lifecycle review in `Laundromat.sol`, especially whether deposit participation and escrowed value stay aligned through withdrawal

## Useful Context
- Audit attention has been highly concentrated in a single contract: `src/Laundromat.sol`
- The strongest durable signal so far is a retained high-severity issue involving zero-cost repeated deposits enabling round completion and theft of escrowed funds from a partially filled round
- Early review included broader state-changing flow tracing, but the lasting cross-round pattern is specifically the interaction between round filling and the multi-step withdrawal flow
