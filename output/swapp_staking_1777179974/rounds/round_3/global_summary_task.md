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
- `Staking.sol` — consistent audit hotspot; focus remains on `deposit`, `withdraw`, `emergencyWithdraw`, `manualEpochInit`, Compound interaction/interest paths, and epoch snapshot/accounting helpers
- `Contract.sol` — wrapper/container used to inspect embedded `Staking.sol`; still not a separate logic hotspot
- embedded `SafeERC20.sol` — lightly checked for transfer-handling assumptions that interact with staking payout safety

## Issue Directions Seen
- Token/accounting mismatch paths: credited stake or cleared claims can diverge from actual assets moved, especially with non-standard ERC-20 return behavior and failed external integrations
- Emergency/exit-path fragility: exit logic appears incomplete under stress, including accounting cleanup drift and stablecoin pools lacking a protocol-native fallback when Compound redemption is unavailable
- Epoch progression and snapshot integrity: historical pool-size/balance views and epoch-dependent flows remain sensitive to stale or mutable state, with dormant pools showing liveness dependence on manual epoch backfilling
- Withdrawal gating/liveness edge cases: withdraw-related state transitions may be blocked or refreshable in unintuitive ways, especially around skipped epochs and low-impact calls
- Compound integration safety: external `mint` / `redeem` success is weakly enforced, so redemption failures or liquidity constraints can propagate into internal accounting and withdrawal availability

## Useful Context
- Audit attention remains concentrated in one contract, and the dominant risk pattern is state-accounting consistency under real asset-movement failures rather than privilege misuse
- The same shared accounting surfaces recur across normal withdrawals, emergency exits, manual epoch initialization, and historical-view helpers, indicating strong coupling between liveness and bookkeeping correctness
- External asset-handling assumptions stay weak in two persistent ways: token transfers may be trusted even when they signal failure, and Compound-style integrations are often treated as effectively available unless they hard-revert
- Historical and epoch-management helpers are part of the effective attack surface because current-state behavior can affect both past-epoch reads and whether later user actions remain executable


## Latest Round Summary
# Round 3 Summary

## Agent: codex
- files touched: `Contract.sol` only; work focused on the embedded `Staking.sol` logic, with brief checks of embedded token-transfer/helper code such as `SafeERC20.sol`
- files revisited / highest-attention files: `Staking.sol` received the clear majority of attention, especially deposit/withdraw, epoch snapshotting, Compound interest redemption, and pool-size read paths
- main issue directions investigated: token/accounting mismatches around transfers and external integrations; emergency/withdraw liveness edge cases; epoch initialization and historical snapshot integrity; Compound redemption / liquidity interactions; raw `balanceOf`-driven accounting for non-stable pools
- promising but not retained directions: fee-on-transfer loss on withdrawal (`F-009` in agent output but not retained after merge); hardcoded June 2021 epoch-start bricking fresh pools (`F-012` in agent output but not retained after merge); general transfer-handling assumptions in embedded ERC-20 helper code were probed but not retained as separate findings

## Cross-Agent Status
- main overlap in file/area attention: only `codex` is present in this round’s logs, with attention concentrated on `Staking.sol`
- notable differences in attention: no cross-agent differences are visible from the provided round logs
- underexplored but suspicious files/functions if clearly supported by the logs: embedded helper/library code inside `Contract.sol` was only lightly checked; within `Staking.sol`, epoch initialization/backfill paths and Compound interaction helpers remained active scrutiny areas even where findings were not retained

## Retained Findings
- `F-010`: retained concern that non-stable pool snapshots trust live token balances rather than tracked stake totals, allowing pool-size/accounting divergence
- `F-011`: retained low-confidence concern that permissionless interest-sweep functions can be used to front-run stablecoin withdrawals and worsen liquidity shortfalls


Output only markdown.
