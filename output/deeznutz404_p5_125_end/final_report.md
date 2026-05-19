# Audit Report

**Total findings:** 4

## High (1)

### F-001: Anyone can front-run and permanently hijack the mirror/base link

**Confidence:** high | **Locations:** `0xb57e874082417b66877429481473cf9fcd8e0b8a/contracts/DN404Reflect.sol:928, 0xb57e874082417b66877429481473cf9fcd8e0b8a/contracts/DN404Mirror.sol:443`

The mirror-link handshake authenticates only a calldata argument against the stored `deployer`, but never authenticates `msg.sender`. Any address can call the mirror fallback with selector `linkMirrorContract(address)` and pass the expected deployer address, causing `baseERC20` to be set to the attacker's address before the real base calls `initialize()`.

**Impact:** A third party can permanently brick deployment or hijack the NFT mirror. Once `baseERC20` is set, the legitimate base can no longer link, so initialization reverts and the intended DN404 pair cannot be brought online.

**Paths:**

- Attacker learns the mirror's expected `deployer` value from deployment data or storage.

- Before the owner calls `initialize()`, the attacker directly calls the mirror fallback with `linkMirrorContract(address)` and supplies that deployer address.

- The mirror stores the attacker's address as `baseERC20`; the later legitimate `_linkMirrorContract()` call hits `AlreadyLinked` and `initialize()` reverts.

*Round 1 | Agents: codex_1*

---

## Medium (3)

### F-003: NFT transfers bypass the configured transfer tax for every whole-`_WAD` chunk

**Confidence:** high | **Locations:** `0xb57e874082417b66877429481473cf9fcd8e0b8a/contracts/DN404Reflect.sol:557, 0xb57e874082417b66877429481473cf9fcd8e0b8a/contracts/DN404Reflect.sol:697, 0xb57e874082417b66877429481473cf9fcd8e0b8a/contracts/DN404Mirror.sol:334`

ERC20 transfers compute `tFee` and reduce the transferred reflected amount, but mirror-driven NFT transfers move exactly `_WAD` worth of reflected balance with no fee deduction. Holders can therefore move balances in NFT-sized chunks through the ERC721 path while avoiding the configured reflection tax.

**Impact:** The token's intended fee/reflection economy can be materially bypassed. Users who route transfers through NFTs avoid most or all transfer tax on whole-`_WAD` amounts, reducing reflections for other holders and shifting the fee burden onto users who use the ERC20 path.

**Paths:**

- A holder accumulates one or more NFTs representing whole `_WAD` balances.

- Instead of calling ERC20 `transfer`, the holder transfers those positions via `DN404Mirror.transferFrom` or `safeTransferFrom`.

- `_transferFromNFT()` debits and credits `rOwned` using the full `_WAD` amount without applying `_reflectFee`, so only any residual dust moved through ERC20 is taxed.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-004: Excluded accounts cannot ever be re-included into reflections

**Confidence:** high | **Locations:** `0xb57e874082417b66877429481473cf9fcd8e0b8a/contracts/DeezNutz.sol:178, 0xb57e874082417b66877429481473cf9fcd8e0b8a/contracts/DeezNutz.sol:194`

`includeAccount()` checks `require(!accountAddressData.isExcluded, "Account is already excluded")`, which is the inverse of the condition needed to re-include an excluded address. The function therefore reverts on exactly the accounts it is supposed to restore.

**Impact:** Any address excluded from reflections becomes permanently excluded. If the owner excludes a treasury, market-making wallet, or other operational account, the token's reflection accounting can remain permanently skewed with no on-chain recovery path.

**Paths:**

- The owner calls `excludeAccount(account)` on a live address.

- A later attempt to restore that address with `includeAccount(account)` hits the inverted `require` and reverts immediately.

- The excluded account can no longer be returned to normal reflection participation.

*Round 1 | Agents: codex_1*

---

### F-005: Ownership is assigned to `tx.origin`, not the actual deployer

**Confidence:** high | **Locations:** `0xb57e874082417b66877429481473cf9fcd8e0b8a/contracts/DeezNutz.sol:73, 0xb57e874082417b66877429481473cf9fcd8e0b8a/@openzeppelin/contracts/access/Ownable.sol:38`

The constructor passes `tx.origin` into `Ownable`, so the initial owner is the outermost EOA rather than `msg.sender`. Deployments through factories, multisigs, relayers, or other contract-based flows therefore assign admin control to a different address than the deploying contract.

**Impact:** Factory or contract-based deployments can lose atomic setup and end up controlled by an unexpected EOA. That unexpected owner can unilaterally initialize the token, configure fees, reveal metadata, enable trading, or block the intended deployment flow from completing.

**Paths:**

- A factory, multisig module, or relayer deploys the token contract.

- Because the constructor uses `tx.origin`, ownership is assigned to the originating EOA instead of the deploying contract/account abstraction.

- The unexpected owner, rather than the intended deployer, controls `initialize()` and the remaining privileged functions.

*Round 1 | Agents: codex_1, opencode_1*

---
