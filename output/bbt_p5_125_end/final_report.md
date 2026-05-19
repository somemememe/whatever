# Audit Report

**Total findings:** 3

## Critical (1)

### F-001: Anyone can replace the registry and grant themselves mint authority

**Confidence:** high | **Locations:** `0x74463ed91bfa45bca06d59e8b383a89709842f69/contracts/token/BBTOKENv2.sol:31, 0x74463ed91bfa45bca06d59e8b383a89709842f69/contracts/token/BBTOKENv2.sol:36, 0x74463ed91bfa45bca06d59e8b383a89709842f69/contracts/token/BBTOKENv2.sol:52`

`setRegistry()` is completely unrestricted. `mint()` trusts the current `registry` to decide whether `msg.sender` matches one of the whitelisted subsystem addresses, so any caller can first point `registry` at a malicious contract and then satisfy `_isAuthorizedAddress()` with attacker-controlled return values.

**Impact:** A permissionless attacker can mint arbitrary amounts of BBT, destroying scarcity and draining value from holders or any protocol that prices or collateralizes BBT. The same primitive can also brick all legitimate minting by setting `registry` to `address(0)`, an EOA, or a contract that reverts on lookup.

**Paths:**

- Attacker deploys a fake registry whose `getContractAddress("Savings")` returns the attacker's address, calls `setRegistry(fakeRegistry)`, then calls `mint(attacker, arbitraryAmount)`.

- Attacker calls `setRegistry(address(0))` or points `registry` at a non-conforming contract, causing future `_isAuthorizedAddress()` lookups inside `mint()` to revert.

*Round 1 | Agents: codex_1, opencode_1*

---

## High (2)

### F-002: Configured `maxSupply` is never enforced, so the token cap is meaningless

**Confidence:** high | **Locations:** `0x74463ed91bfa45bca06d59e8b383a89709842f69/contracts/token/BBTOKENv2.sol:13, 0x74463ed91bfa45bca06d59e8b383a89709842f69/contracts/token/BBTOKENv2.sol:18, 0x74463ed91bfa45bca06d59e8b383a89709842f69/contracts/token/BBTOKENv2.sol:31, 0x74463ed91bfa45bca06d59e8b383a89709842f69/contracts/token/BBTOKENv2.sol:56`

`maxSupply` is written during `initialize()` and `setMaxSupply()`, but no code ever checks it. The initializer can mint `_initSupply` larger than `_maxSupply`, and later `mint()` calls never enforce `totalSupply() + _amount <= maxSupply`.

**Impact:** Any promise of a hard cap is false. The initial supply can be created above the advertised cap, and any authorized minter can inflate supply arbitrarily afterward, breaking tokenomics and any downstream assumptions that rely on bounded issuance.

**Paths:**

- Deployment initializes the token with `_initSupply > _maxSupply`; the transaction still succeeds because `initialize()` never validates the cap.

- After deployment, any address recognized by the registry keeps calling `mint()` even after total supply has already exceeded `maxSupply`.

*Round 1 | Agents: codex_1, opencode_1*

---

### F-003: The proxy deployment would be first-caller capturable if it was deployed without initialization calldata

**Confidence:** low | **Locations:** `0x74463ed91bfa45bca06d59e8b383a89709842f69/contracts/token/BBTOKENv2.sol:18, 0x3541499cda8ca51b24724bb8e7ce569727406e04/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:77, 0x3541499cda8ca51b24724bb8e7ce569727406e04/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:93, 0x3541499cda8ca51b24724bb8e7ce569727406e04/_etherscan_meta.json:8`

The artifact set shows this `BBToken` implementation is used behind a `TransparentUpgradeableProxy`, while `initialize()` is a public `initializer`. If the proxy was deployed with empty `_data`, any non-admin caller could invoke `initialize()` through the proxy before the intended operator, because transparent proxies forward non-admin calls to the implementation.

**Impact:** A missed or delayed initialization would let an attacker seize the live proxy's token state, mint the initial supply to themselves, and set an arbitrary `maxSupply`. This is a full deployment takeover, but it depends on the proxy actually having been deployed without init calldata, which is not provable from the source bundle alone.

**Paths:**

- Proxy is deployed with empty `_data`; before the operator initializes it, an external non-admin account calls `initialize(attackerSupply, attackerCap)` on the proxy and receives the initial mint.

*Round 1 | Agents: codex_1*

---
