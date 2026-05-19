# Global Audit Memory

## Scope Touched
- `Staking.sol` — dominant audit surface across `deposit()`, `withdraw()`, `emergencyWithdraw()`, epoch accounting, stable/non-stable routing, and Compound-facing stablecoin flows
- Epoch snapshot surfaces (`getEpochUserBalance`, `getEpochPoolSize`, `manualEpochInit`) — recurring concern around historical snapshot correctness, lazy initialization/backfilling, and epoch-0/bootstrap state corruption
- Interest extraction paths in `Staking.sol` — repeated attention on how “interest” is computed/swept versus unsolicited token or cToken balances
- Compound integration helpers / `CTokenInterface.sol` — supporting risk surface for mint return-code handling, allowance cleanup, and deposit-path liveness
- ERC20 interaction layer / `IERC20.sol` and `SafeERC20.sol` — transfer/approval semantics remain important, including unchecked returns, fee-on-transfer behavior, rebases, and direct-transfer balance distortion

## Issue Directions Seen
- Deposit / pool accounting can diverge from economically intended stake when code credits requested amounts or trusts live token balances instead of tracked stake
- Epoch-based accounting remains fragile: historical denominators and inherited snapshots can stay mutable or be reset through initialization/backfilling behavior, especially around bootstrap epochs
- Non-stable pool-size logic is especially exposed to accounting poisoning from direct transfers, rebases, and other balance changes outside normal staking flows
- Permissionless balance/interest extraction can misclassify unsolicited assets as collectible yield, creating sweep-to-team risk
- External token / protocol interactions remain a persistent risk when Compound/ERC20 return paths, approvals, or failure cleanup are not handled cleanly, causing accounting drift or deposit freezes
- Emergency and epoch-control paths continue to show liveness/griefing potential when shared timing or initialization state is globally influenced

## Useful Context
- The strongest cross-round signal still clusters in `Staking.sol`; durable themes are accounting desynchronization, snapshot integrity, and external-balance contamination rather than isolated arithmetic bugs
- Cross-round convergence is strongest on denominator correctness: user balances, pool totals, “interest,” and external/live balances can fall out of sync in ways that affect rewards or asset custody assumptions
- Historical epoch reads are suspicious whenever they depend on present balances or lazily initialized state rather than fixed snapshots; epoch-0/bootstrap handling is a repeated hotspot
- Stablecoin staking paths deserve continued attention because Compound mint failures and leftover approvals create both accounting and liveness edge cases
- Reward/referral/claim areas have been explored, but durable retained issues so far remain concentrated in snapshot/accounting drift, interest sweeping, and Compound deposit behavior
