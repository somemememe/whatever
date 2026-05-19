# Global Audit Memory

## Scope Touched
- `0x0e511aa1a137aad267dfe3a6bfca0b856c1a3682/Contract.sol` — single-file target embedding Balancer core logic
- Embedded `BPool.sol` flows — dominant focus across agents; token accounting, joins/swaps, `gulp()`, and exit-path behavior repeatedly surfaced
- Embedded `BMath.sol` / `BNum.sol` — pricing, rounding, and fixed-point math reviewed as supporting risk surface, but no durable math-specific issue retained yet
- Embedded `BToken.sol` — allowance/approval mechanics and BPT behavior were inspected, mostly as secondary context rather than retained issue source

## Issue Directions Seen
- Internal reserve accounting can desynchronize from real token balances, especially around joins/swaps and `gulp()` interactions
- Pool logic assumes ERC20 transfers are truthful/successful in ways that may let malicious, fee-on-transfer, deflationary, or rebasing tokens distort accounting
- Exit paths depend on outbound token transferability; finalized pools can become partially unexitable if a bound token later blocks transfers
- Single-asset and other `BPool.sol` exit/accounting branches remain a recurring suspicious area even when not all paths were deeply retained
- Math primitive scrutiny (`bpow`, `bdiv`, rounding) has been a recurring direction, but so far more as supporting context than confirmed root cause

## Useful Context
- Cross-agent overlap is strongest on embedded `BPool.sol`; the audit has consistently centered on asset-accounting integrity rather than governance-style concerns
- Durable retained themes cluster around mismatch between Balancer’s internal bookkeeping and actual token behavior at the ERC20 boundary
- Broader themes like controller privilege, MEV/slippage framing, and approval races were explored but not retained as cross-round core memory
- The most stable audit context is that non-standard token semantics are the key stressor for this target, affecting pricing, mint/burn math, and withdrawal liveness through shared accounting assumptions
