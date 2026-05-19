# Audit Report

**Total findings:** 2

## Critical (2)

### F-001: Balancer LP collateral can be overvalued from transient pool state during Balancer exit callbacks

**Confidence:** high | **Locations:** `Contract.sol:286, Contract.sol:291, Contract.sol:294, Contract.sol:300, Contract.sol:302, FlawVerifier.sol:315, FlawVerifier.sol:323, FlawVerifier.sol:357, FlawVerifier.sol:360`

The PoC shows `SturdyOracle.getAssetPrice(cB_stETH_STABLE)` being read immediately before `Balancer.exitPool(...)` and again from `receive()` while `exitPool` is still executing and sending native ETH to the caller. Because the reentrant callback observes the Balancer pool in an intermediate state, solvency-sensitive logic can see a temporarily inflated B-stETH-STABLE price instead of the post-exit price.

**Impact:** An attacker can make an undercollateralized position appear healthy long enough to pass collateral checks and extract value against an overstated LP valuation. The exploit comments indicate the collateral price spikes by roughly 3x during the callback, enough to support debt that should otherwise be unsafe and create protocol bad debt.

**Paths:**

- joinBalancerPool -> depositCollateralAndBorrow -> exitBalancerPool -> Balancer.exitPool -> receive -> SturdyOracle.getAssetPrice / health-factor-dependent logic

*Round 1 | Agents: codex*

---

### F-002: Collateral-disable state can be permanently committed using the transiently inflated health factor

**Confidence:** high | **Locations:** `Contract.sol:294, Contract.sol:306, Contract.sol:310, Contract.sol:318, FlawVerifier.sol:326, FlawVerifier.sol:327, FlawVerifier.sol:357, FlawVerifier.sol:361`

During the Balancer `exitPool` callback, the attacker calls `setUserUseReserveAsCollateral(CSTECRV, false)` while the Balancer LP collateral is temporarily overpriced. After `exitPool` finishes and the LP price returns to normal, the disabled-collateral state remains in effect, and the attacker successfully calls `withdrawCollateral(STECRV, 1_000 ether, ...)` to remove the steCRV that was actually needed to support the loan.

**Impact:** A temporary oracle distortion can be converted into a permanent collateral-removal state change, letting borrowers strip real collateral from an open position and leave the protocol undercollateralized once prices normalize. This turns the transient pricing bug into realizable asset loss and bad debt.

**Paths:**

- exitBalancerPool -> receive -> setUserUseReserveAsCollateral(CSTECRV,false) -> withdrawCollateralAndLiquidation -> withdrawCollateral(STECRV)

*Round 1 | Agents: codex*

---
