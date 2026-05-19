# Audit Report

**Total findings:** 4

## Critical (2)

### F-001: Anyone can steal VISR from any EOA that has approved the hypervisor

**Confidence:** high | **Locations:** `contracts/RewardsHypervisor.sol:43, contracts/RewardsHypervisor.sol:60, contracts/RewardsHypervisor.sol:61, contracts/RewardsHypervisor.sol:64`

In the EOA branch of `deposit`, the contract never checks that `msg.sender` is the same as `from` or is otherwise authorized by `from`. Any caller can invoke `deposit(visrDeposit, victim, attacker)` and rely on the victim's pre-existing ERC20 allowance to the hypervisor, causing the contract to pull VISR from the victim while minting the resulting `vVISR` shares to the attacker-controlled `to` address.

**Impact:** Any EOA that has approved the hypervisor can have its approved VISR balance permissionlessly converted into attacker-owned shares and then redeemed, resulting in direct theft of user funds.

**Paths:**

- Victim approves `RewardsHypervisor` to spend VISR

- Attacker calls `deposit(amount, victim, attacker)`

- `RewardsHypervisor` transfers VISR from the victim via `safeTransferFrom`

- `RewardsHypervisor` mints the corresponding `vVISR` shares to the attacker

- Attacker withdraws those shares for the victim's VISR

*Round 1 | Agents: codex*

---

### F-002: Malicious visor contracts can mint completely unbacked shares

**Confidence:** high | **Locations:** `contracts/RewardsHypervisor.sol:56, contracts/RewardsHypervisor.sol:57, contracts/RewardsHypervisor.sol:58, contracts/RewardsHypervisor.sol:64`

For contract depositors, `deposit` trusts `IVisor(from).owner()` and `IVisor(from).delegatedTransferERC20(...)` without verifying that any VISR was actually received. A malicious contract can report the attacker as `owner()` and make `delegatedTransferERC20` a no-op, yet still receive freshly minted `vVISR` based on an arbitrary claimed `visrDeposit`.

**Impact:** An attacker can mint a dominant share position with zero backing and then redeem those shares against the pool's real VISR, draining honest depositors and rendering the system insolvent.

**Paths:**

- Attacker deploys a fake contract implementing `owner()` and `delegatedTransferERC20()`

- Fake contract returns the attacker from `owner()` and does not transfer VISR in `delegatedTransferERC20()`

- Attacker calls `deposit(veryLargeAmount, fakeVisor, attacker)`

- Hypervisor mints `vVISR` as if the VISR arrived

- Attacker withdraws the unbacked shares to extract real VISR from the pool

*Round 1 | Agents: codex*

---

## High (2)

### F-003: First depositor can seize all VISR that reaches the hypervisor before initialization

**Confidence:** high | **Locations:** `contracts/RewardsHypervisor.sol:50, contracts/RewardsHypervisor.sol:51, contracts/RewardsHypervisor.sol:80`

When `vvisr.totalSupply()` is zero, `deposit` mints shares 1:1 with `visrDeposit` and ignores any VISR already sitting in the hypervisor. If VISR is transferred directly into the hypervisor before the first share mint, the first depositor can contribute only a dust amount, receive the full initial share supply, and later redeem essentially the entire pre-seeded VISR balance.

**Impact:** Any VISR that is accidentally sent, pre-funded, or otherwise accumulated in an uninitialized hypervisor can be captured almost entirely by the first depositor.

**Paths:**

- VISR is transferred directly to the hypervisor before any `vVISR` shares exist

- Attacker becomes the first depositor with a minimal deposit

- Because total supply is zero, the attacker receives shares 1:1 only for the dust deposit

- Attacker withdraws those initial shares and receives the full hypervisor VISR balance, including the pre-existing VISR

*Round 1 | Agents: codex*

---

### F-004: Donation-based inflation can force later depositors to receive zero or too few shares

**Confidence:** high | **Locations:** `contracts/RewardsHypervisor.sol:52, contracts/RewardsHypervisor.sol:53, contracts/RewardsHypervisor.sol:61, contracts/RewardsHypervisor.sol:64`

Share issuance uses floor division against the current `visr.balanceOf(address(this))` and provides no `minShares` or slippage protection. An attacker who already owns shares can donate VISR directly to the hypervisor to inflate the asset balance seen by `deposit`, so a victim's subsequent deposit mints drastically fewer shares or even zero shares while still transferring the victim's VISR in full.

**Impact:** A frontrunner can grief or steal from depositors: if the manipulated ratio drives minted shares to zero, the victim's entire deposit becomes value for existing shareholders, and the attacker can later redeem their shares for the victim's VISR.

**Paths:**

- Attacker first acquires a share position

- Attacker transfers VISR directly to the hypervisor to increase `visr.balanceOf(address(this))` without minting new shares

- Victim submits `deposit` without any minimum-share bound

- Floor division mints zero or too few `vVISR` to the victim, but the victim's VISR is still transferred in

- Attacker later withdraws their shares and captures some or all of the victim's deposit

*Round 1 | Agents: codex*

---
