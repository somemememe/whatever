# Audit Report

**Total findings:** 5

## Critical (1)

### F-001: Reentrancy can reuse an uncommitted FNFT id and merge distinct positions into one series

**Confidence:** high | **Locations:** `contracts/Revest.sol:68, contracts/Revest.sol:94, contracts/Revest.sol:122, contracts/Revest.sol:184, contracts/Revest.sol:276, contracts/Revest.sol:377, contracts/Revest.sol:379, contracts/FNFTHandler.sol:40, contracts/FNFTHandler.sol:46, contracts/FNFTHandler.sol:43, contracts/FNFTHandler.sol:51`

`Revest` reads `getNextId()` before making external calls, while `FNFTHandler` only increments `fnftsCreated` after `_mint()`/receiver callbacks finish. A malicious `IAddressLock` trigger or ERC1155 recipient can therefore reenter another mint/split/deposit path before the counter advances, causing multiple economically distinct operations to reuse the same `fnftId`.

**Impact:** Distinct positions can be collapsed onto the same ERC1155 id, cross-wiring lock metadata, vault accounting, and balances. Depending on which write wins, this can enable theft against the wrong backing, incorrect redemption, or permanent lockup of collateral.

**Paths:**

- Call `mintAddressLock()` with a trigger that reenters another mint path from `IAddressLock.createLock()` before the outer mint completes.

- Mint to an attacker-controlled ERC1155 receiver and reenter from `onERC1155Received`/`onERC1155BatchReceived` before `fnftsCreated` is incremented.

- Call `splitFNFT()` or `depositAdditionalToFNFT()` and reenter during the intermediate ERC1155 mint, causing the new series id to collide with another operation.

*Round 1 | Agents: codex_1, opencode_1*

---

## High (2)

### F-002: ETH sent for WETH-backed mints is wrapped into Revest and never forwarded to the vault

**Confidence:** high | **Locations:** `contracts/Revest.sol:337, contracts/Revest.sol:339, contracts/Revest.sol:349, contracts/Revest.sol:359, contracts/Revest.sol:363, contracts/Revest.sol:368, contracts/Revest.sol:372`

`doMint()` wraps all `msg.value` into WETH held by `Revest`, spends at most `flatWeiFee` from that balance, and still pulls the full FNFT deposit from the caller via `safeTransferFrom`. The wrapped remainder is neither transferred to the vault nor refunded.

**Impact:** Users attempting to fund WETH-backed mints with ETH lose the ETH they sent while still needing separate WETH balance and allowance for the actual deposit. The extra WETH accumulates stranded in `Revest` and is not claimable through the FNFT.

**Paths:**

- Call any `mint*()` function with `fnftConfig.asset == WETH` and `msg.value > flatWeiFee`.

- `Revest` wraps the ETH, uses only `flatWeiFee`, then pulls `totalQuantity * depositAmount` WETH from the caller again.

*Round 1 | Agents: codex_1*

---

### F-003: Fee-on-transfer tokens can mint or top up FNFTs with less collateral than accounting assumes

**Confidence:** high | **Locations:** `contracts/Revest.sol:265, contracts/Revest.sol:286, contracts/Revest.sol:289, contracts/Revest.sol:353, contracts/Revest.sol:368, contracts/Revest.sol:372`

Both minting and additional deposits book vault state using nominal amounts (`totalQuantity * depositAmount` or `quantity * amount`) without measuring how many tokens actually arrive after `safeTransferFrom`. Deflationary, taxed, or other fee-on-transfer ERC20s therefore leave FNFTs undercollateralized from inception or top-up.

**Impact:** FNFT holders can redeem against less backing than the protocol records. Withdrawals may later fail, become first-come-first-served, or socialize losses across series if balances are aggregated by asset in the vault.

**Paths:**

- Mint an FNFT whose `asset` charges a transfer fee; the vault receives less than `totalQuantity * depositAmount` but accounting is created at full face value.

- Call `depositAdditionalToFNFT()` for a series backed by a fee-on-transfer token; the series is credited by the requested top-up even though fewer tokens arrive.

*Round 1 | Agents: codex_1, opencode_1*

---

## Low (2)

### F-004: Additional-deposit deadline is enforced backwards

**Confidence:** high | **Locations:** `contracts/Revest.sol:243`

`depositAdditionalToFNFT()` requires `depositStopTime < block.timestamp || depositStopTime == 0`, which allows deposits only after the configured stop time instead of before it.

**Impact:** Series meant to stop accepting added collateral at a deadline remain mutable after that deadline, while legitimate top-ups before the deadline revert. This breaks issuance-window and collateral-immutability assumptions.

**Paths:**

- Create an FNFT with non-zero `depositStopTime`.

- Try `depositAdditionalToFNFT()` before the deadline and observe a revert; try again after the deadline and observe success.

*Round 1 | Agents: codex_1*

---

### F-005: Address-lock mints accept non-compliant trigger addresses and can permanently lock funds

**Confidence:** high | **Locations:** `contracts/Revest.sol:129, contracts/Revest.sol:131, contracts/Revest.sol:132, contracts/Revest.sol:137`

`mintAddressLock()` creates and binds an address lock even when `trigger` does not implement `IAddressLock`; it only conditionally calls `createLock()` and never reverts for EOAs or non-compliant contracts. That leaves the FNFT tied to a lock target that may not support later unlock checks.

**Impact:** Users or integrators can mint collateral into address-lock positions that can never become unlockable, causing permanent fund lockup.

**Paths:**

- Call `mintAddressLock()` with an EOA as `trigger`.

- Call `mintAddressLock()` with a contract that fails ERC165 detection or otherwise does not implement the required `IAddressLock` behavior.

*Round 1 | Agents: codex_1*

---
