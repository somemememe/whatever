# Global Audit Memory

## Scope Touched
- `FlawVerifier.sol` — dominant audit surface across rounds; attention stays on `executeOnOpportunity()`, `_tryCycle()`, liquidation/balance-check logic, and the composed probe/swap/liquidation path, with issue directions around open execution, treasury custody, native-balance success checks, and unsafe external interaction
- `FlawVerifier.sol` helper and call-wrapper surfaces — `_attempt()`, `_call0()`, `_call1()`, `_call2()`, `_safeBalanceOf()`, `_safeApprove()`, selector/probing helpers, and returndata/balance wrappers repeatedly matter because value-bearing external calls, approvals, permissive call handling, and callback exposure are concentrated there
- `FlawVerifier.sol` payable/ETH-receipt behavior — public payable entry plus `receive()`/`fallback()` remains relevant to profit accounting, state injection, and reentrant call-shape review
- `FlawVerifier.sol` hard-coded token/router endpoints — durable scope item because fixed mainnet assumptions can misroute value or break deployment assumptions on other networks
- `Counter.sol` — briefly revisited for simple access-control / state-integrity concerns; still low-signal and shallow relative to `FlawVerifier.sol`

## Issue Directions Seen
- Treasury/value flow may be lost, trapped, or degraded because execution traverses multiple external steps without a robust end-to-end profitability invariant
- Main strategy execution remains broadly triggerable, keeping permissionless treasury-touching execution as a recurring direction
- Profit/success signals remain sensitive to native ETH/WETH balance changes, payable entrypoints, and external balance injection or spoofing
- Swap/liquidation paths continue to suggest extraction risk from weak output guarantees and balance-sensitive execution
- Broad or persistent approvals plus blind or weakly constrained low-level interactions remain a central destructive-call / side-effect direction
- External target interaction keeps reentrancy and callback-capable flows in scope, including risk from untrusted token/router behavior and permissive return-data handling
- Fixed address assumptions remain a retained direction: hard-coded endpoints create wrong-chain or value-sink risk when environment assumptions differ
- `Counter.sol` only contributes a minor recurring direction around unrestricted state mutation, but has not shown comparable signal

## Useful Context
- Cross-round signal is overwhelmingly concentrated in `FlawVerifier.sol`; absence of comparable findings elsewhere should not be read as broad safety
- The most durable pattern is unsafe composition inside one strategy path: approvals, probing, swaps, liquidation, helper-wrapped external calls, and ETH receipt all happen while the contract is actively custodying value
- Correctness depends on the whole opportunity cycle ending profitably; success of individual helpers, balance deltas, or subcalls is not a sufficient safety signal
- Helper-layer behavior matters almost as much as core strategy logic because accounting, approvals, returndata handling, and external-call safety are delegated into wrappers
- Helper call surfaces are repeatedly flagged as risky interaction points, but some remain less deeply inspected than the main `_tryCycle` execution slice
- `Counter.sol` remains low-coverage and low-signal; durable audit memory is still driven by the main execution contract
