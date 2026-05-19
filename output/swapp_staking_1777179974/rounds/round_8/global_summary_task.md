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
- `Staking.sol` — persistent hotspot; repeated focus on `deposit`, `withdraw`, `emergencyWithdraw`, `getInterest`, `getInterestFromCompound`, `checkInterestFromCompound`, `manualEpochInit`, epoch/history helpers, `processReferrals`, `notContract`, and Compound mint/redeem plumbing
- Compound-facing stablecoin paths in `Staking.sol` — recurring attention on `_transferToCompound`, `_redeemFromCompound`, `_getCompoundToken`, cToken/stablecoin result handling, approval behavior, fixed token/cToken assumptions, redeem failure handling, and principal-vs-yield classification
- epoch snapshot / lazy-init state in `Staking.sol` — primary cross-round surface; epoch-0 baselines, backfilled snapshots, historical pool-size propagation, and accounting consistency under time progression remain central
- referral/reward helpers in `Staking.sol` — secondary but recurring surface around referral eligibility, “new user” checks, and EOA-only gating interactions with deposit flows
- token transfer helpers / embedded `SafeERC20.sol` and interfaces — secondary review surface for non-standard ERC-20 return semantics that can amplify staking accounting drift
- `Contract.sol` — mainly useful as the container/navigation entry for the embedded staking system rather than as an independent logic surface

## Issue Directions Seen
- Token/accounting mismatch paths: internal stake, principal, or claim accounting can diverge from assets actually moved because of non-standard ERC-20 behavior, approval quirks, external integration failures, or balance-based inference
- Compound integration safety: staking bookkeeping is weakly coupled to `mint` / `redeem` success, redeemable liquidity, fixed address assumptions, and cToken custody details, which can propagate into withdrawal availability or value misclassification
- Interest-sweep classification risk: interest-handling paths appear to infer yield from raw token or cToken balances, creating a durable risk that externally supplied assets are treated as Compound-generated interest
- Epoch progression and snapshot integrity: historical pool-size views remain exposed to mutable or stale state, especially around epoch-0 initialization, lazy backfilling, forward propagation of forged baselines, and time-dependent accounting edges
- Emergency/withdraw liveness fragility: exit flows remain sensitive to liquidity shortfalls, redeem-path failures, incomplete accounting cleanup, and stale or skipped epoch state
- Referral eligibility/gating ambiguity: referral processing has recurring attention around EOA-only restrictions and “new user” qualification logic, especially where deposit token choice or caller classification may affect reward eligibility
- Non-stable pool valuation/snapshot risk: some accounting paths still appear to trust raw balance views over tracked stake totals, leaving room for pool-size divergence

## Useful Context
- Audit attention remains concentrated on one effective contract surface, with the dominant theme being bookkeeping consistency under imperfect asset movement, mutable epoch state, and external liquidity constraints rather than classic access-control misuse
- A durable pattern is reliance on contract balance views to infer economic meaning; this affects both pool snapshots and Compound interest sweeping, including the possibility that direct transfers of relevant assets are mistaken for protocol yield
- The same accounting surfaces recur across normal withdrawals, emergency exits, manual epoch initialization, historical snapshot reads, Compound-backed interest handling, and some referral qualification paths, showing tight coupling between liveness and accounting correctness
- Historical/epoch helpers are part of the live attack surface because present-state mutations can influence both past-epoch reads and later lazy initialization behavior
- Supporting token/Compound wrapper code has stayed secondary; the persistent risk comes mainly from how staking logic consumes balances, approval outcomes, Compound availability assumptions, cToken custody, and lazily populated epoch history
- Referral/reward logic has been inspected but is still less explored than withdrawal, emergency, epoch, and Compound-backed stablecoin flows; the main recurring concern is eligibility/gating consistency rather than a retained concrete exploit
- Fuzzing has been used to pressure epoch/accounting behavior, but at least one apparent divergence collapsed under monotonic-time assumptions, so time-order realism matters when evaluating this surface


## Latest Round Summary
# Round 8 Summary

## Agent: codex
- files touched: `Contract.sol`; extracted temp views of `Staking.sol`, `SafeERC20.sol`, `ReentrancyGuard.sol`, `Address.sol`, and `SafeMath.sol`
- files revisited / highest-attention files: `Staking.sol` dominated attention, especially `withdraw()` and checkpoint/accounting paths around `Staking.sol:186`, `Staking.sol:192`, `Staking.sol:360`-`443`, and `Staking.sol:490`; helper libs were only briefly checked
- main issue directions investigated: same-epoch checkpoint averaging and withdrawal tranche handling; token-wide emergency-withdraw timing/griefing via `lastWithdrawEpochId`
- promising but not retained directions: the dust-withdrawal emergency-exit suppression idea was developed into `F-016` in the draft output but was not retained after merge; brief review of transfer/reentrancy/math helper libraries did not produce a retained issue

## Cross-Agent Status
- main overlap in file/area attention: single-agent round; attention was concentrated on `Staking.sol` withdrawal and checkpoint logic
- notable differences in attention: no cross-agent differences in this round
- underexplored but suspicious files/functions if clearly supported by the logs: the extracted helper libraries and the later `Staking.sol` balance/checkpoint read paths were only lightly inspected relative to the deeper work on withdrawal accounting

## Retained Findings
- retained `F-015`: withdrawal/checkpoint math can preserve inflated same-epoch weight on remaining stake, allowing late deposits to be left behind with overstated effective balance and unfair reward capture


Output only markdown.
