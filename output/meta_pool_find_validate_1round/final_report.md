# Audit Report

**Total findings:** 1

## Critical (1)

### F-001: Possible unbacked mpETH mint via inherited ERC4626 `mint` path

**Confidence:** low | **Locations:** `FlawVerifier.sol:42, FlawVerifier.sol:50, FlawVerifier.sol:67, FlawVerifier.sol:73, FlawVerifier.sol:82`

`FlawVerifier.executeOnOpportunity()` is an exploit harness aimed at a live proxy (`TARGET_PROXY`) and documents a specific assumption: the proxy still exposes an inherited ERC4626 `mint(uint256,address)` path that mints mpETH before collecting equivalent assets from the caller. If the referenced staking proxy actually behaves this way, an attacker can mint unbacked shares, approve the liquid unstake pool, and immediately redeem those shares for ETH. The repo does not include the target staking implementation, so exploitability cannot be confirmed here, but the verifier code is consistent with a realistic drain path against the referenced external system.

**Impact:** If the target proxy truly allows unbacked share minting, attackers can dilute all holders and directly steal ETH from the liquid unstake pool, potentially draining all immediately available pool liquidity in one or more transactions.

**Paths:**

- Call `executeOnOpportunity()`

- Read `liquidUnstakePool()` from `TARGET_PROXY`

- Optionally top up `TARGET_PROXY` with forced ETH to satisfy internal execution assumptions

- Call `IStakingLike(TARGET_PROXY).mint(desiredShares, address(this))` without first transferring backing assets through a normal deposit flow

- Approve the freshly minted mpETH to the liquid unstake pool

- Call `swapmpETHforETH()` to convert unbacked mpETH into ETH

*Round 1 | Agents: codex*

---
