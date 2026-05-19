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
- `Staking.sol` — persistent hotspot; repeated focus on `deposit`, `withdraw`, `emergencyWithdraw`, `getInterest`, `getInterestFromCompound`, `checkInterestFromCompound`, `manualEpochInit`, epoch/history helpers, and Compound mint/redeem plumbing
- Compound-facing stablecoin paths in `Staking.sol` — recurring attention on `_transferToCompound`, `_redeemFromCompound`, `_getCompoundToken`, cToken/stablecoin result handling, approval behavior, fixed token/cToken assumptions, and principal-vs-yield classification
- epoch snapshot / lazy-init state in `Staking.sol` — primary cross-round surface; epoch-0 baselines, backfilled snapshots, and historical pool-size propagation remain central
- token transfer helpers / embedded `SafeERC20.sol` and interfaces — secondary review surface for non-standard ERC-20 return semantics that can amplify staking accounting drift
- referral/reward helpers — adjacent but still notably less explored than withdrawal, epoch, liquidity, and Compound-backed interest flows
- `Contract.sol` — mainly useful as the container/navigation entry for the embedded staking system rather than as an independent logic surface

## Issue Directions Seen
- Token/accounting mismatch paths: internal stake, principal, or claim accounting can diverge from assets actually moved because of non-standard ERC-20 behavior, approval quirks, external integration failures, or balance-based inference
- Compound integration safety: staking bookkeeping is weakly coupled to `mint` / `redeem` success, redeemable liquidity, fixed address assumptions, and cToken custody details, which can propagate into withdrawal availability or value misclassification
- Interest-sweep classification risk: interest-handling paths appear to infer yield from raw token or cToken balances, creating a durable risk that externally supplied assets are treated as Compound-generated interest
- Epoch progression and snapshot integrity: historical pool-size views remain exposed to mutable or stale state, especially around epoch-0 initialization, lazy backfilling, and forward propagation of forged baselines
- Emergency/withdraw liveness fragility: exit flows remain sensitive to liquidity shortfalls, incomplete accounting cleanup, and stale or skipped epoch state
- Non-stable pool valuation/snapshot risk: some accounting paths still appear to trust raw balance views over tracked stake totals, leaving room for pool-size divergence

## Useful Context
- Audit attention remains concentrated on one effective contract surface, with the dominant theme being bookkeeping consistency under imperfect asset movement, mutable epoch state, and external liquidity constraints rather than classic access-control misuse
- A durable pattern is reliance on contract balance views to infer economic meaning; this affects both pool snapshots and Compound interest sweeping, including the possibility that direct transfers of relevant assets are mistaken for protocol yield
- The same accounting surfaces recur across normal withdrawals, emergency exits, manual epoch initialization, historical snapshot reads, and Compound-backed interest handling, showing tight coupling between liveness and accounting correctness
- Historical/epoch helpers are part of the live attack surface because present-state mutations can influence both past-epoch reads and later lazy initialization behavior
- Supporting token/Compound wrapper code has stayed secondary; the persistent risk comes mainly from how staking logic consumes balances, approval outcomes, Compound availability assumptions, cToken custody, and lazily populated epoch history
- Referral/reward logic has been inspected but remains a lower-confidence, less-explored branch relative to the much heavier focus on withdrawal, emergency, epoch, and Compound-backed stablecoin flows


## Latest Round Summary
# Round 7 Summary

## Agent: codex
- files touched: `Contract.sol` (the only in-scope file surfaced by file listing); analysis also centered on `Staking.sol` logic exposed through the embedded contract content and cited finding locations
- files revisited / highest-attention files: highest attention was on `Staking.sol`, especially `withdraw()`, `_redeemFromCompound()`, `getInterestFromCompound()`, `getInterest()`, `processReferrals()`, and `notContract()`
- main issue directions investigated: Compound redeem failure handling versus stablecoin accounting and interest sweeping; referral gating around EOA-only checks; referral “new user” checks versus arbitrary-token deposits; epoch/accounting consistency via fuzzing
- promising but not retained directions: an accounting divergence first appeared in fuzzing, but the agent determined the initial trace relied on impossible time travel and a monotonic-epoch rerun did not reproduce a retained exploit

## Cross-Agent Status
- main overlap in file/area attention: only one agent log is present, so there was no cross-agent overlap this round
- notable differences in attention: none visible from the round logs because only `codex` is recorded
- underexplored but suspicious files/functions if clearly supported by the logs: no separate underexplored hotspot is clearly supported beyond the already inspected `Staking.sol` Compound-withdraw/interest-sweep path and referral path

## Retained Findings
- None retained from this round after merge


Output only markdown.
