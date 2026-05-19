# Audit Report

**Total findings:** 3

## High (1)

### F-001: Periphery mixes balances across users, letting later callers spend stranded ETH or fragment tokens

**Confidence:** high | **Locations:** `0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/FloorPeriphery.sol:221, 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/FloorPeriphery.sol:250, 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/FloorPeriphery.sol:263, 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/FloorPeriphery.sol:270, 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/FloorPeriphery.sol:285, 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/FloorPeriphery.sol:419`

`buyAndClaimVault` does not isolate balances per caller. In native mode, `_executeSwap` forwards the periphery's entire ETH balance to the Universal Router, not the current caller's contribution. In `_claim`, the periphery deposits and spends fragment tokens from `address(this)` while `claimRandomNFT` sends the redeemed NFTs to the current `msg.sender`. Because the contract has no refund or accounting mechanism, any ETH refunded back from the router or any fragment tokens already sitting on the periphery can be consumed by a later caller.

**Impact:** Residual value left on the periphery can be stolen by the next caller. A later user can underpay or pay nothing, consume prior users' refunded ETH or fragment-token balances, and receive the claimed NFTs themselves.

**Paths:**

- A user calls `buyAndClaimVault` with `TransferWay.NativeTransfer`; the router uses less ETH than supplied and refunds unused ETH back to the periphery via `receive()`.

- The refunded ETH remains on the periphery because the contract keeps no per-user accounting and has no withdrawal path.

- A later caller invokes `buyAndClaimVault` in native mode; `_executeSwap` forwards `address(this).balance` and `_claim` transfers the purchased NFTs to that later caller.

- Similarly, if fragment tokens are already held by the periphery, `_claim` deposits/spends those tokens from `address(this)` while sending redeemed NFTs to the current caller.

*Round 1 | Agents: *

---

## Medium (1)

### F-002: An uninitialized UUPS proxy can be seized by the first external caller

**Confidence:** medium | **Locations:** `0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/FloorPeriphery.sol:122, 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/FloorPeriphery.sol:124, 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/library/OwnedUpgradeable.sol:22, 0x49ad262c49c7aa708cc2df262ed53b64a17dd5ee/solc_0.8/openzeppelin/proxy/ERC1967/ERC1967Proxy.sol:22`

`initialize()` is public and sets the owner to `msg.sender`, and upgrades are authorized solely by that owner. The ERC1967 proxy constructor accepts arbitrary `_data`, including an empty payload. If deployment does not atomically initialize the proxy, any external account can call `initialize()` first, become owner, and gain upgrade authority over the proxy.

**Impact:** A deployment race or operational mistake can hand full control of the periphery proxy to an attacker, who can then upgrade to malicious logic, steal assets routed through the periphery, or permanently brick the contract.

**Paths:**

- The proxy is deployed pointing at `FloorPeriphery` with empty or missing initializer calldata.

- Before the intended operator initializes it, an attacker calls `initialize()` through the proxy and becomes owner.

- The attacker uses the owner-controlled UUPS upgrade path to install malicious implementation code.

*Round 1 | Agents: *

---

## Low (1)

### F-003: Directly transferred ERC721s can be permanently trapped in the periphery

**Confidence:** high | **Locations:** `0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/FloorPeriphery.sol:410, 0xeeced9aa487dfb777ee94ab0c86ac0b0b4d3b7bf/src/FloorPeriphery.sol:416`

The periphery accepts any ERC721 via `onERC721Received`, but it exposes no recovery, sweep, or rescue function for NFTs it holds outside the intended fragment flow. An NFT sent directly to the contract can remain there indefinitely.

**Impact:** Users or integrations that transfer NFTs to the periphery by mistake can permanently lose those NFTs.

**Paths:**

- A user or integration calls `safeTransferFrom(..., FloorPeriphery, tokenId)` directly.

- The transfer succeeds because `onERC721Received()` always returns the acceptance selector.

- There is no function that can return or sweep that NFT back out of the periphery.

*Round 1 | Agents: *

---
