# Audit Report

**Total findings:** 5

## Critical (1)

### F-001: Arbitrary `IRestakedETH` contracts can redeem real pool assets with fake tokens

**Confidence:** high | **Locations:** `0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:405, 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:457, 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:464, 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:489`

`withdraw()` accepts any contract address as a restaked token and later trusts that contract for `scaledBalanceOf`, `scaledBalanceToBalance`, `stakedTokenAddress`, and `burn`. An attacker can therefore queue withdrawals backed only by self-issued fake tokens but payable in genuine staked assets already held by Astrid.

**Impact:** An attacker can drain idle staked tokens from the protocol into attacker-controlled claims. Even if the pool lacks enough idle liquidity to steal immediately, a malicious first request can still block the withdrawal queue and lock legitimate users behind it.

**Paths:**

- Deploy a malicious ERC20 that also implements the `IRestakedETH` interface and returns an arbitrary real `stakedTokenAddress()` plus attacker-chosen values for `scaledBalanceOf` and `scaledBalanceToBalance`.

- Mint the fake restaked token to the attacker, approve Astrid, and call `withdraw(fakeToken, amount)`.

- When `_processWithdrawals()` reaches the request, Astrid converts the fake shares into a real staked-token liability, calls attacker-controlled `burn()`, and credits `totalClaimableWithdrawals` for the chosen real asset.

- Call `claim()` to receive real staked tokens from Astrid.

*Round 1 | Agents: codex_1*

---

## High (3)

### F-002: 1:1 minting lets new depositors capture rewards accrued before a manual rebase

**Confidence:** high | **Locations:** `0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:344, 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:377, 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:391`

Deposits always mint `amount` restaked tokens 1:1, while the true asset/share ratio is only corrected later by an admin-triggered `rebase()`. If staking rewards have accrued but `rebase()` has not yet been called, a new depositor can mint against stale supply and buy into previously accrued rewards at a discount.

**Impact:** A large depositor can front-run a positive rebase and siphon already-earned yield from existing restaked-token holders. The larger the unreconciled reward buffer and the attacker's deposit, the larger the dilution of incumbent holders.

**Paths:**

- Wait until backing has increased above restaked-token total supply because delegated positions accrued rewards, but before governance calls `rebase()`.

- Deposit a large amount through `deposit()` and receive `amount` newly minted restaked tokens at the stale 1:1 rate.

- After `rebase()` socializes the previously accrued rewards across all outstanding supply, the attacker's freshly minted balance receives a share of rewards that were earned before they entered.

- Withdraw later to realize the unearned gain at the expense of prior holders.

*Round 1 | Agents: codex_1*

---

### F-003: A single oversized withdrawal can indefinitely block every later withdrawal

**Confidence:** high | **Locations:** `0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:450, 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:452, 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:459, 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:478`

`_processWithdrawals()` is strict FIFO and stops at the first request whose `requestedAmount` exceeds currently idle liquidity. It does not partially fill, skip, or otherwise advance past the blocking request.

**Impact:** Any sufficiently large withdrawal at the head of the queue can freeze all later withdrawals, even when those later requests are small enough to satisfy immediately. If Astrid cannot accumulate enough idle liquidity in one chunk, user withdrawals can remain locked for an unbounded period.

**Paths:**

- Most protocol assets are delegated, leaving only a small idle token balance in Astrid.

- A user submits a legitimate withdrawal request larger than the current idle balance.

- Each `processWithdrawals()` call reaches that request, hits the `break`, and leaves `withdrawalProcessingCurrentIndex` unchanged.

- All later users remain stuck behind the head-of-line request despite having individually serviceable withdrawals.

*Round 1 | Agents: codex_1*

---

### F-004: Legacy queued withdrawals can become permanently unclaimable after redelegation

**Confidence:** medium | **Locations:** `0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:516, 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:530, 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:532, 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:541`

The legacy `completeQueuedWithdrawal()` path reconstructs EigenLayer's `QueuedWithdrawal` using the current `delegatedTo(address(this))` operator instead of the original queued withdrawal data, and it ignores the stored `withdrawalRoot`. Because EigenLayer validates completions against the original queued-withdrawal hash, changing delegation after queueing can make the reconstructed withdrawal irreconcilable with the stored root.

**Impact:** Users with legacy queued withdrawals can be permanently locked out of completion after Astrid redelegates or undelegates, leaving their withdrawn assets stranded in EigenLayer's queue with no working completion path in this contract.

**Paths:**

- A legacy withdrawal is queued while Astrid is delegated to operator A.

- Before the user completes that queued withdrawal, Astrid's delegation changes to operator B or is removed.

- The user calls `completeQueuedWithdrawal()`, which rebuilds the EigenLayer `QueuedWithdrawal` using the current operator instead of the original one.

- EigenLayer root validation fails because the reconstructed struct no longer matches the originally queued withdrawal, and the user has no alternative contract path that uses the stored root.

*Round 1 | Agents: codex_1*

---

## Medium (1)

### F-005: Deposits mint against the requested amount instead of the actual tokens received

**Confidence:** medium | **Locations:** `0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:377, 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:387, 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/AstridProtocol.sol:391, 0x4d5b4b9ccf52bbcfe7b71b3038d8577293779e0c/helpers/Utils.sol:21`

`deposit()` mints `amount` restaked tokens immediately after a raw `transferFrom` call, but never measures the actual balance delta received by Astrid. If a whitelisted staked token is fee-on-transfer, rebases on transfer, or otherwise transfers less than requested while still returning success, Astrid will mint excess restaked supply with insufficient backing.

**Impact:** A depositor can create undercollateralized restaked supply and externalize the shortfall to existing holders and future withdrawers, causing protocol insolvency for the affected asset.

**Paths:**

- A whitelisted staked token transfers less than `amount` to Astrid during `transferFrom`, while returning success.

- Astrid still mints the full `amount` of restaked tokens to the depositor because it never checks the actual tokens received.

- The depositor later withdraws or benefits from rebases as if full backing had been delivered, extracting the missing value from the pool.

*Round 1 | Agents: codex_1*

---
