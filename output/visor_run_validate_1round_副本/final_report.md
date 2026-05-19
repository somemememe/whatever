# Audit Report

**Total findings:** 3

## Critical (2)

### F-001: Anyone can steal approved EOA VISR by depositing from the victim into their own share account

**Confidence:** high | **Locations:** `contracts/RewardsHypervisor.sol:41, contracts/RewardsHypervisor.sol:60, contracts/RewardsHypervisor.sol:61, contracts/RewardsHypervisor.sol:64`

The EOA deposit path never verifies that `msg.sender` is authorized by `from`. Any caller can supply an arbitrary EOA as `from`; if that address has approved the hypervisor, `safeTransferFrom(from, address(this), visrDeposit)` pulls the victim's VISR while `vvisr.mint(to, shares)` credits the shares to the attacker's chosen `to` address.

**Impact:** Any user who grants the hypervisor an allowance can have their approved VISR stolen permissionlessly. The attacker receives the full vVISR position and can later redeem the victim's principal plus any accrued rewards.

**Paths:**

- Victim approves `RewardsHypervisor` to spend VISR.

- Attacker calls `deposit(amount, victimEOA, attacker)`.

- The hypervisor transfers VISR from the victim and mints vVISR to the attacker.

- The attacker later withdraws the stolen position for the underlying VISR.

*Round 1 | Agents: codex*

---

### F-002: A fake `IVisor` contract can mint completely unbacked shares and drain all VISR

**Confidence:** high | **Locations:** `contracts/RewardsHypervisor.sol:50, contracts/RewardsHypervisor.sol:56, contracts/RewardsHypervisor.sol:57, contracts/RewardsHypervisor.sol:58, contracts/RewardsHypervisor.sol:64, contracts/interfaces/IVisor.sol:6, contracts/interfaces/IVisor.sol:7`

For contract depositors, the hypervisor trusts any address with code as an `IVisor` and only checks that `IVisor(from).owner() == msg.sender`. It never verifies that `delegatedTransferERC20` actually transferred VISR, nor does it measure the received balance delta. An attacker can deploy a contract whose `owner()` returns the attacker and whose `delegatedTransferERC20()` is a no-op, then call `deposit` with any nominal amount and still receive freshly minted vVISR shares.

**Impact:** An attacker can mint an arbitrarily large share balance without contributing any VISR, then redeem a proportional amount of the real VISR already held by the hypervisor, draining honest depositors.

**Paths:**

- Attacker deploys a contract implementing `owner()` and `delegatedTransferERC20()`.

- `owner()` returns the attacker and `delegatedTransferERC20()` does not transfer VISR.

- Attacker calls `deposit(hugeAmount, fakeVisor, attacker)`.

- The hypervisor mints shares as though the VISR was received.

- Attacker withdraws those shares against the real VISR in the pool.

*Round 1 | Agents: codex*

---

## High (1)

### F-003: The first depositor can seize any VISR already sitting in the hypervisor

**Confidence:** high | **Locations:** `contracts/RewardsHypervisor.sol:50, contracts/RewardsHypervisor.sol:51, contracts/RewardsHypervisor.sol:52, contracts/RewardsHypervisor.sol:53, contracts/RewardsHypervisor.sol:64`

When `vvisr.totalSupply() == 0`, the contract always sets `shares = visrDeposit` and skips pricing against the existing VISR balance. If VISR has been transferred into the hypervisor before the first share mint, those pre-existing assets are ignored by the initial share issuance.

**Impact:** The first depositor can capture all pre-seeded or accidentally transferred VISR by depositing a trivial amount, receiving 100% of the initial shares, and then withdrawing the entire pool.

**Paths:**

- VISR is transferred into the hypervisor before any vVISR shares exist.

- An attacker makes the first deposit with a very small `visrDeposit`.

- Because total supply is zero, the attacker receives shares 1:1 with their tiny deposit instead of against total assets.

- The attacker withdraws and receives the entire VISR balance, including the pre-existing tokens.

*Round 1 | Agents: codex*

---
