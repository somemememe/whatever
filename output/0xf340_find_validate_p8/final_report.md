# Audit Report

**Total findings:** 2

## Critical (1)

### F-001: Unrestricted `initVRF` lets arbitrary callers set the payout recipient and token

**Confidence:** medium | **Locations:** `0xf340.sol:36, 0xf340.sol:39, 0xf340.sol:67`

The exploit harness directly calls `initVRF(address,address)` from an unprivileged external context and then successfully pulls LINK out of the victim, which supports that `initVRF` lacks effective access control and accepts attacker-chosen configuration values for the downstream payout flow.

**Impact:** Any external account can repoint the victim's payout configuration to an attacker-controlled recipient and selected token, enabling direct theft of assets held for that payout path instead of sending them to the intended protocol-controlled destination.

**Paths:**

- Call `initVRF(attacker, LINK)` on the victim from an arbitrary address.

- Invoke the downstream payout/claim path so the victim transfers LINK to the attacker-controlled recipient.

*Round 1 | Agents: codex*

---

## High (1)

### F-002: Identical payout calls appear replayable and can repeatedly drain the configured token balance

**Confidence:** low | **Locations:** `0xf340.sol:37, 0xf340.sol:41, 0xf340.sol:42, 0xf340.sol:43, 0xf340.sol:49`

After setting the payout configuration once, the exploit loops 80 successful calls to selector `0x607d60e6` with the same `0` argument and never changes any other input, which is strong evidence that the payout path lacks consumption tracking, replay protection, or another one-time-use guard.

**Impact:** If the payout destination is attacker-controlled, the same payout path can likely be invoked over and over to drain the victim's LINK balance instead of paying only a single legitimate amount.

**Paths:**

- First redirect the payout configuration through `initVRF(attacker, LINK)`.

- Repeatedly call `0x607d60e6(0)` until the victim's LINK balance is exhausted.

*Round 1 | Agents: codex*

---
