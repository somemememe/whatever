You maintain a concise global audit memory for future audit agents.

Update the existing global memory by folding in durable observations from the
latest round summary. The goal is an accumulated cross-round audit view, not a
per-round recap.

This memory is optional context only. Findings are stored separately.

Write the updated memory in this exact structure:

# Global Audit Memory

## Scope Touched
- files/contracts/flows that have mattered across rounds, with short issue-direction notes

## Issue Directions Seen
- recurring or promising vulnerability directions seen across the audit

## Useful Context
- compact cross-round observations 

Rules:
- keep it compact
- preserve useful prior context while integrating new durable observations
- prefer stable cross-round patterns over latest-round details
- fold repeated wording into a single clearer observation
- keep the memory descriptive rather than prescriptive

## Existing Global Memory
# Global Audit Memory

## Scope Touched
- `Staking.sol` — dominant audit surface across `deposit()`, `withdraw()`, `emergencyWithdraw()`, epoch accounting, and stable/non-stable liquidity routing
- Epoch snapshot surfaces (`getEpochUserBalance`, `getEpochPoolSize`, `manualEpochInit`) — recurring concern around historical snapshot correctness, initialization/backfilling liveness, and mutable fallback behavior
- Multiplier timing surface (`currentEpochMultiplier()`) — repeatedly inspected as a bootstrap-era accounting edge, though not a retained issue so far
- Compound integration helpers / `CTokenInterface.sol` — supporting risk surface for external protocol return-code handling and liquidity/accounting sync
- ERC20 interaction layer / `IERC20.sol` — transfer semantics remain important, especially unchecked returns, fee-on-transfer behavior, rebases, and direct-transfer balance distortion

## Issue Directions Seen
- Deposit / pool accounting can diverge from economically intended stake when code credits requested amounts or trusts live token balances instead of tracked stake
- Epoch-based accounting remains fragile: historical denominators and snapshots can stay mutable until initialization/backfilling occurs
- Non-stable pool-size logic is especially exposed to accounting poisoning from direct transfers, rebases, and other balance changes outside normal staking flows
- External token / protocol interactions remain a persistent risk when return values or error codes are ignored
- Emergency and epoch-control paths continue to show liveness/griefing potential when shared timing or initialization state is globally influenced

## Useful Context
- Most durable signal still clusters in `Staking.sol`; the highest-value themes are accounting desynchronization and epoch snapshot integrity rather than isolated arithmetic bugs
- Cross-round convergence is strongest on denominator correctness: user balances, pool totals, and external/live balances can fall out of sync in ways that affect reward accounting
- Historical epoch reads are suspicious whenever they can depend on present contract balances or lazily initialized state rather than fixed snapshots
- `manualEpochInit()` and `currentEpochMultiplier()` keep resurfacing as investigation hotspots, but retained findings have so far concentrated on snapshot/accounting drift rather than bootstrap-only edge cases


## Latest Round Summary
# Round 3 Summary

## Agent: codex
- files touched: `Contract.sol`; high-attention review material was the extracted `Staking.sol`, with brief checks of `SafeERC20.sol` and `CTokenInterface.sol`
- files revisited / highest-attention files: `Staking.sol` around `deposit`, `_transferToCompound`, interest-sweep functions, and `manualEpochInit` / epoch snapshot handling
- main issue directions investigated: epoch initialization and snapshot corruption, permissionless interest sweeping of unsolicited assets, Compound mint / allowance failure modes that can freeze stablecoin deposits
- promising but not retained directions: broader reward/referral/claim surface and general epoch/pool accounting paths were searched, but only the three retained directions were carried forward

## Agent: merge-review
- files touched: `Staking.sol` only, as reflected by all retained finding locations
- files revisited / highest-attention files: `Staking.sol` lines tied to epoch-0 initialization, interest extraction, and Compound deposit approval flow
- main issue directions investigated: confirmation/merge of the epoch-0 snapshot reset issue, unsolicited-asset interest sweeping, and failed-mint leftover allowance deposit freeze
- promising but not retained directions: no additional non-retained directions are visible from the provided materials

## Cross-Agent Status
- main overlap in file/area attention: both agents converged on `Staking.sol`, especially epoch snapshot initialization, interest/accounting extraction, and Compound integration paths
- notable differences in attention: codex logs show wider exploratory grep coverage across rewards, referrals, withdraw, deposit, and pool state; merge-review visibility is limited to the three merged findings
- underexplored but suspicious files/functions if clearly supported by the logs: current visible attention is heavily concentrated in `Staking.sol`; codex also searched reward/referral/claim-related paths there, but no retained issue from those areas appears in this round

## Retained Findings
- `F-007`: epoch-0 can be manually reinitialized to zero, corrupting inherited pre-launch stake snapshots
- `F-010`: permissionless interest collection can sweep accidentally transferred stablecoins or cTokens to the team wallet
- `F-011`: a failed Compound mint can leave a non-zero allowance that blocks future stablecoin deposits


Output only markdown.
