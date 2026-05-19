# Global Audit Memory

## Scope Touched
- `contracts/Staking.sol`: primary audit surface across rounds; attention centers on `stake()`, `unstake()`, and `rebase()` with both transfer-accounting and epoch/reward edge cases
- `contracts/interface/IDistributor.sol`, `contracts/interface/IsQWA.sol`: supporting call-surface context for distributor-triggered rebasing and token semantics
- `setDistributor()` and `secondsToNextEpoch()`: lightly explored secondary surfaces around configuration hygiene and overdue-epoch timing behavior

## Issue Directions Seen
- ERC20 interaction safety: unchecked token transfer return values and reliance on nominal amounts rather than actual received/sent balances
- Rebase accounting around time gaps: single-epoch catch-up behavior when multiple epochs are missed
- Epoch-timing extraction: predictable/public `rebase()` boundary enabling late-entry or JIT reward capture
- General control-surface checks around staking remain lower-confidence background directions: reentrancy, zero-address validation, and public-call MEV framing were explored but not retained

## Useful Context
- Cross-round attention is highly concentrated in `Staking.sol`; interfaces mainly matter for understanding external assumptions rather than as standalone risk centers
- The most durable pattern is mismatch between staking-share accounting and real token movement or delayed epoch processing
- Economic/reward-accounting hypotheses have been more productive than generic hygiene issues so far
- Overdue-epoch behavior appeared multiple times as a context point, but the stronger retained concern is reward distribution under missed-epoch and boundary-timing conditions
