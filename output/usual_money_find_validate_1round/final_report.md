# Audit Report

**Total findings:** 2

## High (2)

### F-001: Unprotected V3 reinitializer lets any caller seize the `rtusd0` dependency

**Confidence:** medium | **Locations:** `0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/token/Usd0PP.sol:151, 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/token/Usd0PP.sol:158, 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/token/Usd0PP.sol:459, 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/token/Usd0PP.sol:577`

`initializeV3` is a public `reinitializer(4)` with no access control and no validation that `rtusd0` is the intended contract. If a proxy is upgraded to this implementation without atomically executing the reinitializer, any external account can call `initializeV3` first and permanently set `$.rtusd0` to an attacker-chosen address.

**Impact:** A frontrunner can brick the upgrade or redirect all future `rtusd0` mint/burn calls to a malicious or non-contract target. That breaks the intended coupling between `bUSD0` and `rtUSD0`, can make `reconstruct` succeed without a real redemption-token burn, and can strand users or let `bUSD0` holders bypass the intended two-leg bond invariant after a mis-sequenced upgrade.

**Paths:**

- Admin upgrades the proxy to this implementation without `upgradeToAndCall` data or other atomic initialization -> attacker calls `initializeV3(attackerControlledRt)` before the admin does -> later `mint` and `reconstruct` trust the attacker-controlled `rtusd0` endpoint.

*Round 1 | Agents: codex*

---

### F-002: `bUSD0` holders can redeem backing without burning the paired `rtUSD0`

**Confidence:** high | **Locations:** `0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/token/Usd0PP.sol:232, 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/token/Usd0PP.sol:259, 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/token/Usd0PP.sol:313, 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/token/Usd0PP.sol:343, 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/token/Usd0PP.sol:439, 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/token/Usd0PP.sol:459, 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/token/Usd0PP.sol:556, 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/token/Usd0PP.sol:577, 0x9f2bd21bf8012fce0d5845537c1deff3a89bc85b/src/interfaces/token/IUsd0PP.sol:229`

Each mint deconstructs one USD0 position into two transferable legs: `bUSD0` and `rtUSD0`. However, every redemption path except `reconstruct` (`unwrap`, `unwrapWithCap`, `unwrapPegMaintainer`, `unlockUsd0ppFloorPrice`, and `unlockUSD0ppWithUsual`) burns only `bUSD0` and releases USD0 collateral without also burning the paired `rtUSD0` minted for the same bond.

**Impact:** Once the two legs are split, the `bUSD0` holder can unilaterally consume some or all of the collateral first, leaving the `rtUSD0` holder with an orphaned token that no longer has a matching backed bond to reconstruct. This is direct value extraction from redemption-token holders and breaks the accounting invariant implied by `reconstruct`, which requires both legs to destroy a bond.

**Paths:**

- User mints with `bAssetRecipient = Alice` and `rAssetRecipient = Bob` -> Alice calls `unlockUSD0ppWithUsual`, `unlockUsd0ppFloorPrice`, `unwrapWithCap`, `unwrapPegMaintainer`, or waits for maturity and calls `unwrap` -> USD0 leaves the contract while Bob still holds `rtUSD0` that cannot independently recover the backing.

- Any secondary-market buyer of only `bUSD0` can redeem the backing through the one-legged exit paths, externalizing the loss onto whoever bought or retained the paired `rtUSD0`.

*Round 1 | Agents: codex*

---
