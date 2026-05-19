# Audit Report

**Total findings:** 11

## Critical (4)

### F-002: FSushiBill backdates rewards for fresh beneficiaries because deposits never checkpoint the receiver

**Confidence:** high | **Locations:** `0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBill.sol:60, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBill.sol:61, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBill.sol:71, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBill.sol:109, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBill.sol:128, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBill.sol:155, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiCookV0.sol:89, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiCookV0.sol:90`

`deposit()` checkpoints only `msg.sender`, then mints bill tokens to `beneficiary`. If the beneficiary has never been checkpointed before, their first `claimRewards()` runs `_updatePoints()` with `lastTime == 0` and the beneficiary's current balance, causing accrual from `SousChef.startWeek()` rather than from the actual deposit time.

**Impact:** A fresh address can receive a tiny late deposit and immediately claim historical emissions for weeks when it held no stake, draining fSUSHI rewards from honest bill holders.

**Paths:**

- Wait until multiple reward weeks have accrued, deposit a small amount to a fresh beneficiary, then have that beneficiary call `claimRewards()` to receive retroactive rewards from `startWeek`.

- `FSushiCookV0.cook()` always deposits into `IFSushiBill.deposit(fTokensToUser, beneficiary)` from the helper contract, so first-time cook beneficiaries inherit the same backdated-reward bug automatically.

*Round 1 | Agents: codex_1*

---

### F-003: FarmingLPToken transfers duplicate accrued vault rewards to the recipient

**Confidence:** high | **Locations:** `0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:144, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:155, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:378, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:388, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:389, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:390`

The cumulative reward formula uses `_pointsCorrection` as reward debt, but `_transfer()` adds the same positive correction `(_pointsPerShare * shares)` to both `from` and `to`. That leaves the sender's previously accrued entitlement intact while also crediting the receiver, instead of moving reward debt with the transferred shares.

**Impact:** A holder can split positions across fresh addresses and multiply withdrawable vault rewards, draining Sushi/yield-vault assets owed to the rest of the pool.

**Paths:**

- Accrue Sushi into the yield vault, transfer fLP tokens to one or more fresh addresses, then withdraw from each address to realize duplicated vault balances.

- Repeat share-splitting before claiming or withdrawing to extract a disproportionate share of pooled Sushi rewards.

*Round 1 | Agents: codex_1*

---

### F-005: FlashStrategySushiSwap flash-burn consumes principal-bearing fLP shares while principal accounting stays unchanged

**Confidence:** high | **Locations:** `0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FlashStrategySushiSwap.sol:91, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FlashStrategySushiSwap.sol:119, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FlashStrategySushiSwap.sol:132, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FlashStrategySushiSwap.sol:144, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FlashStrategySushiSwap.sol:155, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FlashStrategySushiSwap.sol:157`

`quoteBurnFToken()` returns a Sushi-denominated share of the strategy's yield, but `burnFToken()` passes that value directly into `IFarmingLPToken.withdraw(yield, address(this))`, where the parameter is fLP shares, not Sushi assets. This burns part of the strategy's principal-bearing fLP position and unwraps LP/Sushi to the burner, yet `_balancePrincipal` is not reduced.

**Impact:** Flash burners can consume assets backing active stakes while protocol accounting still treats the principal as intact, leaving later unstakers unable to receive their promised principal.

**Paths:**

- Users stake fLP through the Flash Protocol, which increases `_balancePrincipal` on the strategy.

- An attacker acquires fTokens and calls `burnFToken()`, causing the strategy to burn its own fLP shares and transfer the resulting LP tokens/Sushi out.

- A later `withdrawPrincipal()` still tries to return the original principal amount even though the strategy no longer holds enough fLP balance, resulting in insolvency or failed unstakes.

*Round 1 | Agents: codex_1*

---

### F-009: FSushiAirdropsVotingEscrow reconstructs old weeks from only the latest voting-escrow checkpoints

**Confidence:** high | **Locations:** `0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:41, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:42, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:55, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:56, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:74, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:75, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:78, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:87, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:93, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:94, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:102`

For every historical week, the contract reads only `userPointHistory(account, userPointEpoch(account))` and `pointHistory(epoch)`, i.e. the most recent voting-escrow checkpoints, instead of searching for the checkpoint at or before the target timestamp. After `claim()` calls `IVotingEscrow.checkpoint()`, those latest checkpoints are typically newer than the historical week being processed, so the code subtracts `timestamp - ts` with `ts > timestamp`, causing underflow/revert or otherwise reconstructing the wrong balances.

**Impact:** Voting-escrow airdrop claims can become unusable or mispriced after normal checkpointing and lock updates, leading to permanent loss of claimable airdrops.

**Paths:**

- A user waits several weeks, then calls `claim()`. The function first calls `IVotingEscrow.checkpoint()`, making the latest global checkpoint current.

- When `_votingEscrowTotalSupply(oldWeekStart)` or `_votingEscrowBalanceOf(account, oldWeekStart)` runs, it uses the latest checkpoint rather than the old-week checkpoint, so historical math reverts or returns incorrect voting power.

- Any later lock update or additional checkpoint preserves the same failure mode for prior weeks.

*Round 1 | Agents: codex_1*

---

## High (5)

### F-001: FSushiBill deposit/withdraw updates bill balances twice, creating unbacked bill supply and inflated reward weight

**Confidence:** high | **Locations:** `0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBill.sol:60, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBill.sol:66, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBill.sol:71, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBill.sol:77, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBill.sol:81, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBill.sol:86`

`deposit()` manually increments `_balanceOf[msg.sender]` and `_totalSupply` before calling `_mint(beneficiary, amount)`, while `withdraw()` manually decrements them before `_burn(msg.sender, amount)`. This double-counts each deposit in bill accounting. When `beneficiary == msg.sender`, one fToken deposit produces 2x bill balance for reward accrual; when `beneficiary != msg.sender`, both addresses end up with redeem/reward state backed by only one deposited fToken.

**Impact:** Bill accounting becomes inflated and partially unbacked. Attackers can over-accrue SousChef rewards relative to their real fToken stake, and cross-account deposits can leave one holder with irredeemable bill balances after the other withdraws the only collateral.

**Paths:**

- Call `deposit(amount, attacker)` so the manual write and `_mint()` both credit the attacker, then accrue/claim rewards against the doubled bill balance.

- Call `deposit(amount, alt)` from an attacker-controlled sender so both sender and beneficiary receive bill state backed by one fToken deposit; one side can withdraw the collateral while the other keeps unbacked reward-bearing balance.

*Round 1 | Agents: codex_1*

---

### F-004: FarmingLPToken mints shares from attacker-controlled spot quotes instead of realized value

**Confidence:** medium | **Locations:** `0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:201, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:208, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:215, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:223, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/libraries/UniswapV2Utils.sol:14, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/libraries/UniswapV2Utils.sol:21`

When LP is deposited, the contract mints fLP shares equal to `quote(router, reserveShare0, path0) + quote(router, reserveShare1, path1)`. The chosen paths are user-supplied and only constrained by their endpoints, so share issuance depends on manipulable `router.getAmountsOut()` spot quotes rather than realized swaps, TWAPs, or any trusted oracle.

**Impact:** A depositor can overstate the Sushi value of the same LP position and mint excess fLP shares, diluting honest holders and later withdrawing an outsized share of LP principal and rewards.

**Paths:**

- Construct thin or manipulated token0->...->SUSHI and token1->...->SUSHI routes, then deposit LP against those routes so `getAmountsOut()` overvalues the position and over-mints fLP.

- Use the inflated fLP shares later in `withdraw()`, `migrate()`, or transfers to capture more LP principal and Sushi yield than was actually deposited.

*Round 1 | Agents: codex_1*

---

### F-006: FSushiBar deposits for another beneficiary split the lock record from the burnable shares

**Confidence:** high | **Locations:** `0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBar.sol:116, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBar.sol:131, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBar.sol:133, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBar.sol:144, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBar.sol:156, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBar.sol:165`

`deposit()` mints `shares` to `beneficiary`, but stores the corresponding time lock in `_locks[msg.sender]`. `withdraw()` later drains only `msg.sender`'s queue and burns only `msg.sender`'s share balance. A third-party deposit therefore separates the unlock record from the shares required to redeem it.

**Impact:** Deposits made for another account can become permanently unrecoverable, stranding both principal and accrued yield because no single address controls both the matured lock and the required shares.

**Paths:**

- Call `deposit(assets, weeks, beneficiary)` with `beneficiary != msg.sender`.

- When the lock matures, `beneficiary` cannot withdraw because their queue is empty, while `msg.sender` cannot withdraw because `_burn(msg.sender, shares)` fails without the minted shares.

*Round 1 | Agents: codex_1*

---

### F-008: Snapshots.valueAt uses the current block timestamp instead of the requested historical timestamp

**Confidence:** high | **Locations:** `0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/libraries/Snapshots.sol:22, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/libraries/Snapshots.sol:23, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/libraries/Snapshots.sol:47, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/libraries/Snapshots.sol:49, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiKitchen.sol:56, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBill.sol:175`

The binary search in `Snapshots.valueAt()` compares snapshot timestamps against `block.timestamp` (`_now`) instead of the function argument `timestamp`. For almost any historical query after the first snapshot, the search walks toward the latest snapshot and returns the current value rather than the value at the requested time.

**Impact:** FSushiKitchen cannot preserve historical pool weights. Later weight changes retroactively alter the `relativeWeightAt()` used for past-week bill claims, redirecting already-earned emissions away from the pools that actually earned them.

**Paths:**

- Rewards accrue for week N under one weight schedule.

- Before users claim, governance updates pool weights.

- `FSushiBill.claimRewards()` asks `relativeWeightAt(pid, (week + 1).toTimestamp())`, but the snapshot helper returns the latest weights instead of week N's weights, mispricing historical rewards.

*Round 1 | Agents: codex_1*

---

### F-010: FSushiAirdropsVotingEscrow.claim() divides by zero on weeks with zero voting-escrow supply

**Confidence:** high | **Locations:** `0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:44, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:48, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:55, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:56, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiAirdropsVotingEscrow.sol:58`

`claim()` computes each week's payout as `((INITIAL_SUPPLY_PER_WEEK >> (week - startWeek)) * balance) / totalSupply` without guarding `totalSupply == 0`. Because every user's first claim starts from `startWeek`, any historical week with no voting-escrow supply causes a division-by-zero revert before the user cursor advances.

**Impact:** If the airdrop starts before any ve locks exist, all later users can be permanently prevented from claiming because their first claim always re-enters the zero-supply week and reverts.

**Paths:**

- Deploy the contract with no initial ve supply for `startWeek` or any later week.

- A user eventually obtains ve balance and calls `claim()`. The loop processes the earlier zero-supply week and reverts on division by zero.

- Since `lastCheckpointOf[msg.sender]` updates only after the loop completes, repeated claims keep reverting on the same historical week.

*Round 1 | Agents: opencode_1*

---

## Medium (2)

### F-007: FSushiBarPriorityQueue overwrites same-timestamp lock snapshots and can lose deposits

**Confidence:** high | **Locations:** `0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FSushiBar.sol:133, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/libraries/FSushiBarPriorityQueue.sol:17, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/libraries/FSushiBarPriorityQueue.sol:70, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/libraries/FSushiBarPriorityQueue.sol:87, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/libraries/FSushiBarPriorityQueue.sol:120`

Each lock snapshot is stored in `mapping(uint256 => Snapshot) snapshots` keyed only by its unlock timestamp. If multiple deposits use the same unlock timestamp, later enqueues overwrite the prior snapshot while duplicate timestamps remain in the heap array. On dequeue, only the last written snapshot is recoverable and the overwritten entry is effectively deleted.

**Impact:** Users making same-timestamp deposits can lose part or all of one matured lock, resulting in permanent loss of principal/yield for the overwritten entry.

**Paths:**

- Make two deposits that resolve to the same unlock timestamp, such as two deposits in the same block with the same `_weeks`.

- At withdrawal time, the first dequeue returns only the last stored snapshot and deletes it; the second identical timestamp dequeues zeros, so one deposit is lost.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-011: FarmingLPToken standard withdraw and migrate paths revert whenever no Sushi yield is currently claimable

**Confidence:** high | **Locations:** `0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:260, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:264, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:274, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:281, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:282, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:311, 0xa44e79a2c9a8965e7a6fa77bf0ca8faf50e6c73e/contracts/FarmingLPToken.sol:319`

Both `withdraw()` and `migrate()` unconditionally call `_claimSushi()`, and `_claimSushi()` reverts with `InsufficientYield()` when `_withdrawableVaultBalanceOf(msg.sender, false) == 0`. As a result, users with zero currently accrued Sushi cannot use the normal exit or migration path even though their LP principal is available.

**Impact:** Principal exits and migrations are permissionlessly DOSed in zero-yield states, forcing users onto emergency flows that skip reward handling and making ordinary withdrawals unavailable until some yield appears.

**Paths:**

- A fresh depositor or a pool with no pending Sushi calls `withdraw(shares, beneficiary)`; `_claimSushi()` sees `withdrawable == 0` and reverts the entire withdrawal.

- The same account tries `migrate()`, but the shared `_claimSushi()` call reverts there as well, leaving only the emergency path.

*Round 1 | Agents: codex_1*

---
