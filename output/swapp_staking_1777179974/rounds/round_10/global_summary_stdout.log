# Global Audit Memory

## Scope Touched
- `Staking.sol` — dominant hotspot across rounds; repeated attention on `deposit`, `withdraw`, `emergencyWithdraw`, `manualEpochInit`, `getEpochPoolSize`, `getCurrentEpoch`, `getInterest*`, `processReferrals`, `notContract`, and Compound mint/redeem plumbing
- withdrawal/checkpoint accounting in `Staking.sol` — central surface around same-epoch stake averaging, tranche handling, checkpoint updates, partial exits, and `lastWithdrawEpochId` / emergency-exit interactions
- epoch snapshot / lazy-init state in `Staking.sol` — persistent cross-round surface; epoch-0 baselines, backfilled snapshots, checkpoint carry-forward, and permissionless future-epoch initialization that can freeze stale pool sizes into later accounting
- Compound-facing stablecoin paths in `Staking.sol` — recurring review of `_transferToCompound`, `_redeemFromCompound`, `_getCompoundToken`, `checkInterestFromCompound`, fixed token/cToken assumptions, result handling, and principal-vs-yield classification
- referral/reward helpers in `Staking.sol` — secondary but recurring surface around referral eligibility, `hasReferrer` / “new user” checks, referrer percentage handling, and EOA-only gating interactions with deposits
- token transfer helpers / embedded `SafeERC20.sol` and interfaces — secondary review surface for non-standard ERC-20 return semantics and transfer-trust assumptions that can amplify staking accounting drift
- `Contract.sol` — mainly the wrapper/container for the embedded staking system rather than an independent logic surface

## Issue Directions Seen
- Token/accounting mismatch paths: internal stake, principal, checkpoint weight, or claim accounting can diverge from assets actually moved because of non-standard ERC-20 behavior, approval quirks, external integration failures, or balance-based inference
- Withdrawal/checkpoint distortion: same-epoch deposits and later partial withdrawals can leave remaining stake with overstated historical weight, and withdrawal-side state updates may interfere with later emergency-exit eligibility
- Epoch progression and snapshot integrity: historical pool-size views remain exposed to mutable or stale state, especially around lazy backfilling, epoch-0 initialization, and permissionless pre-initialization of future epochs whose copied denominators may not be refreshed after later stake changes
- Compound integration safety: staking bookkeeping is weakly coupled to `mint` / `redeem` success, redeemable liquidity, fixed address assumptions, and cToken custody details, which can propagate into withdrawal availability or value misclassification
- Interest-sweep classification risk: interest-handling paths appear to infer yield from raw token or cToken balances, creating a durable risk that externally supplied assets are treated as Compound-generated interest
- Emergency/withdraw liveness fragility: exit flows remain sensitive to liquidity shortfalls, redeem-path failures, shared timing state, zero-value state transitions, incomplete accounting cleanup, and stale or skipped epoch state
- Referral eligibility/gating ambiguity: referral processing repeatedly draws attention around EOA-only restrictions, “new user” qualification, and percentage/eligibility consistency, but remains a weaker direction than epoch, withdrawal, and Compound-backed flows
- Non-stable pool valuation/snapshot risk: some accounting paths still appear to trust raw balance views over tracked stake totals, leaving room for pool-size divergence

## Useful Context
- Audit attention remains concentrated on one effective contract surface, with the dominant theme being bookkeeping consistency under imperfect asset movement, mutable epoch/checkpoint state, and external liquidity constraints rather than classic access-control misuse
- A durable pattern is reliance on contract balance views or cached snapshot math to infer economic meaning; this affects pool snapshots, Compound interest sweeping, and how remaining stake inherits reward weight after same-epoch activity
- Epoch helpers are part of the live attack surface, not passive views: permissionless initialization and lazy propagation can let present actions shape future denominators that later reward/accounting logic treats as authoritative
- Exit sequencing is repeatedly important: withdrawal/emergency flows combine state mutation, epoch bookkeeping, liquidity assumptions, and token-transfer trust, so even zero-amount or failed-transfer edges can matter
- Supporting token and Compound wrapper code stays secondary; the persistent risk comes mainly from how staking logic consumes balances, transfer outcomes, approval results, Compound availability assumptions, cToken custody, and lazily populated epoch history
- Referral/reward logic has been inspected several times but remains less developed than withdrawal, emergency, epoch, and Compound-backed stablecoin flows; recurring concern is eligibility/gating consistency more than a settled exploit
- Fuzzing has been useful for pressure-testing epoch/accounting behavior, but some apparent divergences collapse under monotonic-time assumptions, so time-order realism matters on this surface
