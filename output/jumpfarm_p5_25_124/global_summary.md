# Global Audit Memory

## Scope Touched
- `0x05999eb831ae28ca920ce645a5164fbdb1d74fe9/contracts/Staking.sol` - dominant focus so far; recurring attention on `stake()`, `unstake()`, `rebase()`, constructor epoch initialization, and `secondsToNextEpoch()`, with issue pressure around transfer/accounting correctness, distributor-triggered state transitions, and epoch math

## Issue Directions Seen
- Unchecked ERC20 return values in staking and unstaking paths
- Nominal-amount accounting vs actual received/sent amounts, especially for fee-on-transfer or deflationary token behavior
- Reentrancy / state-ordering risk around `distributor.distribute()` during `rebase()`
- Epoch configuration and time arithmetic edge cases, including zero-length epochs and overdue-epoch handling
- Token issuance semantics in the sTOKEN path were examined but remain unresolved rather than established

## Useful Context
- Audit attention has been concentrated entirely in `Staking.sol`; no broader repo surface has been explored yet
- Cross-round convergence is strongest on staking/unstaking accounting and rebase/distributor interactions
- Access-control, owner-malicious-distributor framing, slippage, mint/burn semantics, and dead-code observations were examined but have not persisted as durable issue directions
- The retained signal so far is mostly around concrete invariant breaks and edge-case state transitions, not governance-trust assumptions
