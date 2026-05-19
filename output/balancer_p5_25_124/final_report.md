# Audit Report

**Total findings:** 3

## High (1)

### F-001: Emergency exits permanently invalidate LinearPool virtual-supply accounting, yet the pool auto-resumes normal operation after the buffer period

**Confidence:** high | **Locations:** `0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol:62, 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol:211, 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol:463, 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol:489, 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol:546, 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol:665, 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-pool-utils/contracts/BasePool.sol:279, 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/helpers/TemporarilyPausable.sol:61, 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-solidity-utils/contracts/helpers/TemporarilyPausable.sol:122`

LinearPool optimizes all normal pricing and rate paths around `_getApproximateVirtualSupply`, which assumes total BPT supply always equals `_INITIAL_BPT_SUPPLY`. Emergency exits explicitly break that invariant by burning BPT, and the contract comments acknowledge the approximation becomes inaccurate. Nevertheless, `getRate()` remains callable and continues using the approximation immediately after emergency burns, and after the buffer period `whenNotPaused` starts passing again automatically, re-enabling swap logic that also relies on the stale approximation.

**Impact:** Once any emergency exit burns BPT, the pool can no longer safely quote `getRate()` and, after automatic unpause, can reopen with permanently wrong BPT pricing or broken math. Remaining LPs and downstream integrations can suffer fund loss, bad accounting, or denial of service, and the pool can become effectively unrecoverable without external migration.

**Paths:**

- Governance pauses the pool during an incident

- LPs use `EMERGENCY_EXACT_BPT_IN_FOR_TOKENS_OUT`, and `BasePool.onExitPool` burns BPT

- `getRate()` keeps dividing by `_getApproximateVirtualSupply`, so its rate becomes inconsistent with real supply

- After the buffer period expires, `TemporarilyPausable` automatically treats the pool as unpaused again

- Normal `onSwap()` paths resume and keep using the stale virtual-supply approximation on a post-burn state

*Round 1 | Agents: codex_1, opencode_1*

---

## Medium (2)

### F-002: `getRate()` can expose transient join/exit state as a manipulable on-chain rate oracle

**Confidence:** low | **Locations:** `0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-pool-utils/contracts/BasePool.sol:205, 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-pool-utils/contracts/BasePool.sol:243, 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-pool-utils/contracts/BasePool.sol:262, 0x9210f1204b5a24742eba12f710636d76240df3d0/@balancer-labs/v2-pool-utils/contracts/BasePool.sol:279, 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol:546, 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol:548, 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/LinearPool.sol:566`

`BasePool.onJoinPool` mints BPT before Vault token balances are settled, and `BasePool.onExitPool` burns BPT before settlement completes. `LinearPool.getRate()` is an unguarded external view that reads live Vault balances together with current BPT supply, so a read-only reentrant call during settlement can observe a supply/balance combination that never exists in a finalized state.

**Impact:** Any downstream protocol that trusts this pool as an on-chain `IRateProvider` can be fed a transiently inflated or deflated rate during join/exit settlement, enabling mispricing, bad collateral accounting, or value extraction. The exploitability depends on the surrounding integration and whether a reentrant read path is available, so confidence is limited.

**Paths:**

- An attacker triggers a join or exit that changes BPT supply inside `BasePool`

- Before Vault balances are fully synchronized, a token hook or other read-only reentrant path calls `getRate()`

- A downstream protocol consumes the transient rate for pricing, minting, or collateral accounting

*Round 1 | Agents: codex_1*

---

### F-003: AaveLinearPool does not enforce that the wrapped token actually matches the Aave rate source it uses for pricing

**Confidence:** low | **Locations:** `0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/aave/AaveLinearPool.sol:50, 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/aave/AaveLinearPool.sol:51, 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/aave/AaveLinearPool.sol:54, 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/interfaces/IStaticAToken.sol:24, 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/interfaces/IStaticAToken.sol:30, 0x9210f1204b5a24742eba12f710636d76240df3d0/contracts/interfaces/IStaticAToken.sol:35`

The constructor only checks that `wrappedToken.ASSET()` equals `mainToken` and stores `wrappedToken.LENDING_POOL()`, but pricing later ignores `wrappedToken.rate()` and instead hardcodes `lendingPool.getReserveNormalizedIncome(mainToken)`. An arbitrary contract can satisfy the lightweight interface checks while having redemption economics below the assumed Aave reserve income, so the pool lacks an on-chain invariant tying wrapped-token value to the rate source used for swaps and BPT pricing.

**Impact:** If an incompatible or malicious wrapper is deployed into this pool, wrapped deposits and swaps can be overvalued, allowing the pool to mint undercollateralized BPT or pay out too much main token. This is a deployment-path and configuration-sensitive issue, so it is lower confidence than a direct runtime exploit.

**Paths:**

- A pool is deployed with a token that implements the `IStaticAToken` surface but is not economically equivalent to Aave's normalized-income model

- The pool prices that token using `getReserveNormalizedIncome(mainToken)` anyway

- Users deposit or swap the wrapped token at an inflated valuation and dilute or drain honest LPs

*Round 1 | Agents: codex_1, opencode_1*

---
