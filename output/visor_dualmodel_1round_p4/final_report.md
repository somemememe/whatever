# Audit Report

**Total findings:** 4

## Critical (3)

### F-001: Fake or short-paying `IVisor` deposits can mint unbacked shares and drain pooled VISR

**Confidence:** high | **Locations:** `contracts/RewardsHypervisor.sol:50, contracts/RewardsHypervisor.sol:51, contracts/RewardsHypervisor.sol:52, contracts/RewardsHypervisor.sol:53, contracts/RewardsHypervisor.sol:56, contracts/RewardsHypervisor.sol:57, contracts/RewardsHypervisor.sol:58, contracts/RewardsHypervisor.sol:64`

`deposit()` prices shares from the caller-supplied `visrDeposit` before moving funds, and the contract-path only checks that `from` is a contract whose `owner()` equals `msg.sender`. It never verifies that `delegatedTransferERC20()` actually transferred the full amount, nor does it measure the Hypervisor's VISR balance delta before minting `shares`.

**Impact:** An attacker can deploy a fake visor whose `owner()` returns the attacker and whose `delegatedTransferERC20()` transfers nothing, or too little, then mint vVISR backed by no real VISR. Those unbacked shares can be redeemed against the pool's existing VISR, stealing funds from honest depositors.

**Paths:**

- Deploy a contract that implements `owner()` and `delegatedTransferERC20()` but does not send VISR.

- Call `deposit(largeAmount, fakeVisor, attacker)` so the Hypervisor computes shares from `largeAmount` and mints them anyway.

- Receive freshly minted vVISR without contributing equivalent VISR.

- Call `withdraw(mintedShares, attacker, attacker)` to redeem real VISR from the pool.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-002: The first depositor can seize any VISR that reaches the Hypervisor before shares exist

**Confidence:** high | **Locations:** `contracts/RewardsHypervisor.sol:50, contracts/RewardsHypervisor.sol:51, contracts/RewardsHypervisor.sol:64, contracts/RewardsHypervisor.sol:80`

When `vvisr.totalSupply()` is zero, `deposit()` mints shares 1:1 with `visrDeposit` and ignores any VISR already held by the Hypervisor. `withdraw()` later redeems against the full on-contract VISR balance.

**Impact:** If VISR is sent to the Hypervisor before the first legitimate deposit, the first depositor can make a dust deposit, receive the entire initial share supply, and then withdraw essentially all pre-seeded VISR. This can steal protocol seed funds, mistakenly transferred VISR, or any rewards funded before initialization.

**Paths:**

- VISR is transferred into a freshly deployed Hypervisor before any vVISR exists.

- An attacker becomes the first depositor and deposits a trivial amount.

- Because `totalSupply()==0`, the attacker receives the initial shares 1:1 with the dust deposit.

- The attacker withdraws those shares and receives the full VISR balance, including the pre-existing seed.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-004: Anyone can steal approved VISR by depositing from another user's address and minting shares to themselves

**Confidence:** high | **Locations:** `contracts/RewardsHypervisor.sol:41, contracts/RewardsHypervisor.sol:43, contracts/RewardsHypervisor.sol:47, contracts/RewardsHypervisor.sol:48, contracts/RewardsHypervisor.sol:60, contracts/RewardsHypervisor.sol:61, contracts/RewardsHypervisor.sol:64`

On the EOA path, `deposit()` never requires `msg.sender == from`. It simply calls `visr.safeTransferFrom(from, address(this), visrDeposit)` and then mints the resulting vVISR to arbitrary `to`. Therefore, any caller can spend another user's VISR allowance to the Hypervisor and route the newly minted shares to themselves.

**Impact:** Any user who has approved the Hypervisor to spend VISR, which is the normal prerequisite for depositing, can have that approved VISR pulled into the pool by an attacker. The attacker receives the vVISR shares and can immediately redeem them, turning ordinary allowances into direct theft.

**Paths:**

- A victim approves the Hypervisor to spend their VISR so they can deposit later.

- An attacker calls `deposit(amount, victim, attacker)` while the approval is still active.

- The Hypervisor transfers VISR from the victim via `safeTransferFrom` and mints vVISR shares to the attacker.

- The attacker keeps the shares or calls `withdraw()` to extract the corresponding VISR value.

*Round 1 | Agents: merge_review*

---

## High (1)

### F-003: Direct VISR donations let existing shareholders force zero or underpriced mints and capture later deposits

**Confidence:** high | **Locations:** `contracts/RewardsHypervisor.sol:51, contracts/RewardsHypervisor.sol:52, contracts/RewardsHypervisor.sol:53, contracts/RewardsHypervisor.sol:64`

For nonzero supply, share issuance uses the raw `visr.balanceOf(address(this))` denominator and rounds down, but `deposit()` offers no minimum-share or slippage check. Existing shareholders can change that denominator by transferring VISR directly to the Hypervisor immediately before a victim deposit.

**Impact:** A large incumbent holder can sandwich deposits by temporarily donating VISR to inflate price-per-share, causing the victim to mint too few shares or even zero shares. The attacker can then withdraw their position and reclaim the temporary donation plus captured value from the victim's deposit.

**Paths:**

- Acquire a large share of existing vVISR supply.

- Front-run a victim `deposit()` by transferring VISR directly to the Hypervisor.

- The victim's deposit mints too few shares, or zero shares, because the denominator was artificially inflated.

- Redeem the attacker's shares after the victim deposit to recover the donation and extract the victim's lost value.

*Round 1 | Agents: codex_1, opencode_1*

---
