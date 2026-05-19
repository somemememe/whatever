# Audit Report

**Total findings:** 17

## High (6)

### C-001: Zero-quorum auto-futarchy can be farmed to mint arbitrary shares or loot and capture governance

**Confidence:** high | **Locations:** `Moloch.sol:305, Moloch.sol:307, Moloch.sol:325, Moloch.sol:347, Moloch.sol:433, Moloch.sol:573, Moloch.sol:583, Moloch.sol:602, Moloch.sol:863, Moloch.sol:868, Moloch.sol:988`

Two high-severity conditions compose into a stronger exploit chain: if the DAO leaves both quorum gates at zero, `state()` treats a tied or losing proposal as immediately `Defeated`, so the first NO voter can finalize the NO side at once; if futarchy rewards are configured to mint local shares or loot and `autoFutarchyCap == 0`, each proposal can attach an arbitrarily large reward that `cashOutFutarchy()` later pays by minting fresh governance units.

**Impact:** An attacker with minimal voting power can repeatedly open funded proposals, cast a single NO vote, resolve immediately, and mint unbounded shares or loot. This enables rapid governance inflation and likely full governance capture.

**Paths:**

- DAO sets `quorumBps == 0` and `quorumAbsolute == 0`.

- DAO sets `rewardToken` to `address(this)` or `address(1007)` and leaves `autoFutarchyCap == 0`.

- Attacker repeatedly opens proposals with large auto-futarchy rewards.

- For each proposal, attacker casts one NO vote, calls `resolveFutarchyNo(id)`, and then `cashOutFutarchy(id, amount)` to mint shares or loot.

*Round 1 | Agents: codex_1*

---

### F-001: Permit receipts can replay already-executed proposal intents

**Confidence:** high | **Locations:** `Moloch.sol:264, Moloch.sol:493, Moloch.sol:632, Moloch.sol:659, Moloch.sol:966`

Proposals and permits share the same `_intentHashId`, but `spendPermit()` never checks `executed[tokenId]`. If the DAO executes an intent through `executeByVotes()` and also leaves a permit outstanding for the same `(op,to,value,data,nonce)`, the permit holder can execute the same action again. Permits with `count > 1` are likewise replayable despite sharing one global execution tombstone.

**Impact:** Single-use governance actions such as treasury payouts, approvals, configuration changes, or arbitrary delegatecalls can be executed multiple times, bypassing the one-shot execution guarantee enforced in the vote path.

**Paths:**

- DAO issues `setPermit(op,to,value,data,nonce,spender,count)` for some action.

- The same intent is executed once via `executeByVotes(op,to,value,data,nonce)`.

- The permit holder later calls `spendPermit(op,to,value,data,nonce)` and re-executes the action.

*Round 1 | Agents: codex_1*

---

### F-002: Futarchy reward pools are only accounted for, not escrowed, so winning receipts can become unpayable

**Confidence:** high | **Locations:** `Moloch.sol:336, Moloch.sol:521, Moloch.sol:565, Moloch.sol:569, Moloch.sol:616, Moloch.sol:988`

The futarchy system tracks rewards in `F.pool` and derives `payoutPerUnit` from that accounting value, but it never escrows or reserves the underlying ETH, ERC20, shares, or loot. Those assets remain spendable through normal DAO flows, and on YES outcomes `executeByVotes()` runs arbitrary proposal code before futarchy resolution.

**Impact:** Winning receipt holders can hold claims that revert or pay only partially because the treasury has already spent the assets that `F.pool` assumes are still there. This breaks payout guarantees and lets proposals or later treasury actions consume rewards owed to winners.

**Paths:**

- A futarchy market is opened or funded so `F.pool` increases.

- Before winners cash out, the same treasury assets are spent via another DAO action or by the proposal itself on the YES path.

- `cashOutFutarchy()` later pays from the live treasury via `_payout(...)`, which reverts or underfunds if the assets are gone.

*Round 1 | Agents: codex_2*

---

### F-003: Zero-quorum futarchy lets the first NO voter resolve and drain rewards immediately

**Confidence:** high | **Locations:** `Moloch.sol:305, Moloch.sol:347, Moloch.sol:433, Moloch.sol:573, Moloch.sol:583`

When `quorumBps == 0` and `quorumAbsolute == 0`, `state()` returns `Defeated` whenever `forVotes <= againstVotes`. On an auto-funded futarchy proposal, a single NO vote is therefore enough to make the proposal immediately resolvable through `resolveFutarchyNo()` without any waiting period for the rest of governance.

**Impact:** An attacker with minimal voting power can front-run governance, instantly finalize the NO side, and claim the futarchy reward pool before any YES coalition can respond. If nobody has NO receipts yet, the pool can also become stuck with no claimant.

**Paths:**

- DAO enables auto-futarchy while both quorum gates remain zero.

- Attacker opens or targets a proposal with a funded futarchy pool.

- Attacker casts `castVote(id, 0)`.

- Attacker or any caller executes `resolveFutarchyNo(id)` and then `cashOutFutarchy(id, amount)`.

*Round 1 | Agents: codex_1*

---

### F-004: Auto-futarchy can mint unbounded shares or loot as rewards

**Confidence:** high | **Locations:** `Moloch.sol:307, Moloch.sol:325, Moloch.sol:602, Moloch.sol:863, Moloch.sol:868, Moloch.sol:988`

The DAO can set `rewardToken` to the local mint sentinels `address(this)` or `address(1007)`, and `openProposal()` does not inventory-cap those reward types. With `autoFutarchyCap == 0`, each new proposal can earmark an arbitrary amount, and `cashOutFutarchy()` later pays winners by minting fresh shares or loot through `_payout()`.

**Impact:** A coalition can spam proposals and farm unlimited governance inflation without the DAO holding corresponding assets, causing severe dilution and likely governance capture.

**Paths:**

- DAO sets `setFutarchyRewardToken(address(this))` or `setFutarchyRewardToken(address(1007))`.

- DAO sets `setAutoFutarchy(param, 0)`.

- Attackers repeatedly open proposals, win the rewarded side, and call `cashOutFutarchy()` to mint fresh shares or loot.

*Round 1 | Agents: codex_1*

---

### F-009: DAO deployment addresses can be frontrun and initialized with attacker-chosen parameters and initCalls

**Confidence:** high | **Locations:** `Moloch.sol:243, Moloch.sol:2078, peripheral/SafeSummoner.sol:1085`

The CREATE2 salt for new DAO deployments depends only on `initHolders`, `initShares`, and `salt`, while `orgName`, governance settings, renderer, metadata, and arbitrary `initCalls` are excluded. An attacker who learns a planned deployment tuple can frontrun it, deploy to the exact same deterministic DAO address first, and initialize that DAO with attacker-chosen configuration and `initCalls` that execute as the DAO.

**Impact:** The intended deployment can be permanently hijacked or DoSed. A frontrunner can occupy the victim's expected DAO/token addresses, install malicious governance settings, permits, allowances, or module configuration during initialization, and cause the legitimate deployment to revert on address collision.

**Paths:**

- Victim submits or publishes a deployment using known `salt`, `initHolders`, and `initShares`.

- Attacker copies those three fields, changes governance parameters, metadata, renderer, or `initCalls`, and sends their own summon transaction first.

- CREATE2 lands at the victim's predicted address, the attacker-controlled initialization runs, and the victim's original deployment later reverts because the address is already occupied.

*Round 2 | Agents: codex_1, codex_2*

---

## Medium (7)

### F-005: BondingCurveSale exact-in buys can undercharge when the solver overshoots

**Confidence:** high | **Locations:** `peripheral/BondingCurveSale.sol:176, peripheral/BondingCurveSale.sol:183, peripheral/BondingCurveSale.sol:209, peripheral/BondingCurveSale.sol:211, peripheral/BondingCurveSale.sol:214, peripheral/BondingCurveSale.sol:223`

In `buyExactIn()`, LINEAR and XYK sales derive `amount` analytically, then if recomputed `_cost(...)` exceeds `msg.value`, the function clamps `cost` down to `msg.value` instead of reducing `amount`. The buyer still receives the oversized token amount.

**Impact:** Exact-in buyers can repeatedly receive more sale inventory than they paid for, extracting discounted shares or loot and draining DAO sale inventory over time.

**Paths:**

- Configure a LINEAR or XYK bonding-curve sale.

- Call `buyExactIn()` with a value where the analytical `amount` overshoots once `_cost(...)` is recomputed with rounded-up pricing.

- The function sets `cost = msg.value`, spends allowance for the larger `amount`, and transfers all of those tokens to the buyer.

*Round 1 | Agents: codex_2*

---

### F-006: ClassicalCurveSale.configure accepts externally circulating tokens that can later dump against curve ETH

**Confidence:** high | **Locations:** `peripheral/ClassicalCurveSale.sol:264, peripheral/ClassicalCurveSale.sol:285, peripheral/ClassicalCurveSale.sol:320, peripheral/ClassicalCurveSale.sol:769, peripheral/ClassicalCurveSale.sol:816`

`configure()` escrows only `cap + lpTokens` from the caller and never verifies that the token's remaining supply is locked in the sale. Later, `sell()` and `sellExactOut()` redeem any holder's tokens against curve ETH as long as `amount <= sold`, so pre-existing external holders can offload unrelated inventory into buyer-funded liquidity.

**Impact:** If a configured token already circulates outside the contract, those outside holders can drain ETH raised from honest curve buyers even though they never purchased through the curve.

**Paths:**

- A creator configures an already-circulating ERC20 with `configure()`.

- Users buy from the curve, increasing `sold` and `raisedETH`.

- An external holder of the same token calls `sell()` or `sellExactOut()` and redeems against the curve's ETH.

*Round 1 | Agents: codex_1*

---

### F-007: Proposal-threshold checks use current votes while proposal snapshots use the previous block

**Confidence:** high | **Locations:** `Moloch.sol:283, Moloch.sol:285, Moloch.sol:290, Moloch.sol:347`

`openProposal()` enforces `proposalThreshold` with `getVotes(msg.sender)` from the current block, but fixes the proposal snapshot at `block.number - 1`. A proposer can therefore borrow or transiently obtain enough voting power in the current block to pass the threshold while being evaluated against a snapshot where those votes never existed.

**Impact:** The proposal threshold no longer reliably gates proposal creation. Attackers can use temporary voting power to open proposals they should not be able to create at the actual voting snapshot.

**Paths:**

- Temporarily obtain enough delegated votes in the current block.

- Call `openProposal()` or `castVote()` before those votes disappear.

- The threshold check passes on current votes, while the stored proposal snapshot points to the prior block where the proposer lacked the threshold.

*Round 1 | Agents: codex_2*

---

### F-010: LPSeedSwapHook pool reservations can be squatted for arbitrary future token pairs

**Confidence:** high | **Locations:** `peripheral/LPSeedSwapHook.sol:242, peripheral/LPSeedSwapHook.sol:280, peripheral/LPSeedSwapHook.sol:287`

`LPSeedSwapHook.configure` is permissionless and reserves `poolDAO[poolId]` for any caller without verifying that the caller is a DAO or that the token pair is live. Because reservation is based only on the token addresses and hook configuration, an attacker can preclaim a victim's predicted future pool id, including pools that depend on deterministically derived DAO token addresses.

**Impact:** A squatter can block a DAO from configuring or deploying a seeded pool for a known future pair. If the victim tries to configure LP seeding inside deployment-time `initCalls`, the preclaimed reservation can also cause the entire summon flow to revert.

**Paths:**

- Attacker predicts the victim's future pair, such as `ETH` and a deterministic `shares` address.

- Attacker calls `LPSeedSwapHook.configure(...)` first from an arbitrary EOA, which stores `poolDAO[poolId] = attacker`.

- Victim later calls `configure` for the same pair and hits `existing != address(0) && existing != msg.sender`, reverting with `Unauthorized()`.

*Round 2 | Agents: codex_1*

---

### F-011: LPSeedSwapHook does not block pre-reservation pool creation, so later seeding can inherit attacker-set pool pricing

**Confidence:** medium | **Locations:** `peripheral/LPSeedSwapHook.sol:307, peripheral/LPSeedSwapHook.sol:373, peripheral/LPSeedSwapHook.sol:385, peripheral/LPSeedSwapHook.sol:525`

For LP operations, `beforeAction` only blocks when `poolDAO[poolId]` is already registered and unseeded; unregistered pools are still allowed. If an attacker creates the matching hook pool before the DAO reserves it, `seed()` later adds liquidity with `amount0Min=0` and `amount1Min=0` into that existing pool rather than a fresh one, accepting the attacker-controlled reserve ratio.

**Impact:** The hook's intended frontrun protection can be bypassed. A victim DAO may seed treasury assets into an attacker-initialized pool at a distorted price, causing immediate value loss or launching the market with a manipulated ratio.

**Paths:**

- Before the DAO reserves `poolId`, attacker initializes a pool using the same hook and token pair.

- DAO later configures LP seeding for that pair without detecting that the pool already exists with attacker-controlled reserves.

- When `seed()` runs, it calls `addLiquidity(..., 0, 0, ...)` against the attacker-created pool and inherits the manipulated pricing.

*Round 2 | Agents: codex_1*

---

### F-012: ShareBurner destroys the DAO's entire share balance, not just unsold sale inventory

**Confidence:** high | **Locations:** `peripheral/ShareBurner.sol:41, peripheral/ShareBurner.sol:43, peripheral/SafeSummoner.sol:773`

`burnUnsold` delegatecalls into the DAO and burns `IShares(shares).balanceOf(address(this))`, which in DAO context is the DAO's full current share balance. The permit installed by `SafeSummoner` therefore authorizes a post-deadline caller to burn every share held by the DAO at execution time, regardless of whether those shares are actually unsold sale inventory.

**Impact:** If the DAO later reacquires shares for treasury operations, buybacks, LP seeding leftovers, refunds, or any other reason, any caller can irreversibly burn them after the deadline. This can destroy treasury assets and materially alter governance power.

**Paths:**

- DAO is deployed with `saleBurnDeadline` so the ShareBurner permit is installed.

- Before or after the deadline, the DAO accumulates shares for reasons unrelated to unsold inventory.

- After the deadline, any user calls `ShareBurner.closeSale`.

- The delegatecall burns the DAO's entire current share balance.

*Round 2 | Agents: codex_2*

---

### F-014: Proposals can be proposed, passed, and executed without any minimum voting period

**Confidence:** high | **Locations:** `Moloch.sol:347, Moloch.sol:433, Moloch.sol:493`

`proposalTTL` is only enforced as an expiry, not as a minimum voting window, so a proposal becomes `Succeeded` as soon as current tallies satisfy quorum and FOR exceeds AGAINST and can then be executed immediately whenever `timelockDelay` is zero.

**Impact:** A proposer who already controls enough prior-block voting power can open a proposal, satisfy quorum with an early vote, and execute it before other holders have a meaningful opportunity to react. Governance therefore collapses to near-instant execution unless a nonzero timelock is configured.

**Paths:**

- A holder with enough past voting power calls `castVote(id, 1)` on an unopened proposal, which auto-opens it at `block.number - 1` and records a passing tally.

- With `timelockDelay == 0`, the same holder or another caller invokes `executeByVotes(...)` as soon as `state(id)` reports `Succeeded`.

- The proposal executes before the rest of governance can cast offsetting votes.

*Round 3 | Agents: codex_1*

---

## Low (4)

### C-002: Fake DAOs can drain stray ETH or ERC20 balances from singleton sale and vesting peripherals

**Confidence:** high | **Locations:** `peripheral/ShareSale.sol:55, peripheral/ShareSale.sol:74, peripheral/ShareSale.sol:81, peripheral/ShareSale.sol:106, peripheral/ShareSale.sol:124, peripheral/ShareSale.sol:131, peripheral/ShareSale.sol:148, peripheral/BondingCurveSale.sol:78, peripheral/BondingCurveSale.sol:100, peripheral/BondingCurveSale.sol:128, peripheral/BondingCurveSale.sol:136, peripheral/BondingCurveSale.sol:152, peripheral/BondingCurveSale.sol:167, peripheral/BondingCurveSale.sol:214, peripheral/BondingCurveSale.sol:223, peripheral/TapVest.sol:55, peripheral/TapVest.sol:65, peripheral/TapVest.sol:81, peripheral/TapVest.sol:82, peripheral/TapVest.sol:100, peripheral/TapVest.sol:103, peripheral/TapVest.sol:105`

Several global singleton peripherals key configuration only by `msg.sender` and later trust an arbitrary `dao` parameter for `allowance()` and `spendAllowance()`. A fake DAO can therefore fabricate allowance, no-op the allowance spend, and trigger payouts from the singleton's own balances in `ShareSale`, `BondingCurveSale`, and `TapVest`.

**Impact:** Any ETH or ERC20 balances accidentally or forcibly left on these singleton contracts can be stolen at near-zero net cost by an attacker-controlled fake DAO, with payments recycled back to the attacker or only temporarily prefunded.

**Paths:**

- Attacker deploys a fake DAO whose `allowance()` reports spendable balance and whose `spendAllowance()` does nothing.

- The fake DAO configures `ShareSale` or `BondingCurveSale` for a token that already sits in the singleton, then the attacker buys through the sale flow.

- The singleton forwards payment to the fake DAO, trusts the fake allowance accounting, and transfers its own existing token balance to the attacker.

- The fake DAO configures `TapVest` with an attacker beneficiary and a token or ETH balance already sitting in the singleton.

- The attacker temporarily funds the fake DAO enough to satisfy any balance cap checks, calls `claim()`, receives payout from the singleton, and then withdraws the temporary funding.

*Round 3 | Agents: codex_2*

---

### F-008: Zero proposal threshold lets arbitrary outsiders pre-open and hijack deterministic proposal IDs

**Confidence:** medium | **Locations:** `Moloch.sol:264, Moloch.sol:278, Moloch.sol:283, Moloch.sol:299, Moloch.sol:419`

Proposal IDs are deterministic and do not include the proposer, and `openProposal()` performs no authorization when `proposalThreshold == 0`. Any address can therefore pre-open a chosen intent hash first, fixing `snapshotBlock`, `createdAt`, and `proposerOf` before the intended proposer acts.

**Impact:** Attackers can grief governance by forcing stale snapshots, stealing proposer-only cancellation rights, or causing targeted proposal IDs to age out, forcing honest users to rotate nonces or rebuild proposals.

**Paths:**

- Attacker computes a target proposal ID from `proposalId(op,to,value,data,nonce)`.

- With `proposalThreshold == 0`, attacker calls `openProposal(id)` first.

- The legitimate proposer is stuck with the attacker's snapshot and proposer record or must abandon that nonce.

*Round 1 | Agents: codex_1*

---

### F-013: Launched ERC20 tokens embed unconditional transfer privileges for the hook, ZAMM, and ZRouter

**Confidence:** medium | **Locations:** `peripheral/ClassicalCurveSale.sol:1584, peripheral/ClassicalCurveSale.sol:1585, peripheral/ClassicalCurveSale.sol:1586, peripheral/ClassicalCurveSale.sol:1624`

The custom ERC20 created by `launch()` skips allowance checks whenever `msg.sender` is the sale hook, the hardcoded ZAMM address, or the hardcoded ZRouter address. Those contracts therefore retain standing authority to move any holder's tokens without approval.

**Impact:** Every launched token inherits a hidden trust assumption in those privileged contracts. If any of them is compromised, upgraded maliciously, or exposes an arbitrary transfer path, token holders can be drained without granting allowances.

**Paths:**

- A token is launched through `ClassicalCurveSale.launch`.

- A privileged address such as the hook, ZAMM, or ZRouter calls `transferFrom(holder, attacker, amount)`.

- The token skips the holder's allowance check and transfers the holder's funds.

*Round 2 | Agents: codex_2*

---

### F-015: Undocumented uint96 vote and badge bounds can brick large-supply or large-holder share operations

**Confidence:** medium | **Locations:** `Moloch.sol:1523, Moloch.sol:1535, Moloch.sol:1815, Moloch.sol:1820`

Share voting checkpoints and badge accounting downcast to `uint96`, but the share token itself uses `uint256` balances and supply, so mints and transfers that push delegate votes, tracked voting power, or a holder balance above `2^96 - 1` revert unexpectedly.

**Impact:** A DAO can become unable to initialize, mint, transfer, or rebalance very large share positions once these hidden bounds are crossed. This can block sales, treasury distributions, or migrations for high-supply deployments even though the ERC20 accounting itself would otherwise support the amounts.

**Paths:**

- A mint or transfer increases a holder's share balance above `type(uint96).max`, causing badge bookkeeping to revert and the enclosing share operation to fail.

- A mint, transfer, or delegation update pushes a checkpointed vote value above `type(uint96).max`, causing the checkpoint write to revert and blocking the enclosing share movement.

*Round 3 | Agents: codex_1*

---
