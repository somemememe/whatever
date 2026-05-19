# Audit Report

**Total findings:** 1

## Critical (1)

### F-001: Read-only reentrancy during Balancer exit transiently overvalues BPT collateral and lets attackers remove real collateral

**Confidence:** medium | **Locations:** `Contract.sol:276, Contract.sol:288, Contract.sol:291, Contract.sol:294, Contract.sol:302, Contract.sol:306, Contract.sol:318, Contract.sol:324`

The exploit contract shows that `Balancer.exitPool(...)` can invoke the attacker's `receive()` hook before the Balancer pool state is fully settled. Inside that reentrant window, `SturdyOracle.getAssetPrice(cB_stETH_STABLE)` reports an inflated value for the Balancer LP collateral, and the protocol accepts `lendingPool.setUserUseReserveAsCollateral(address(csteCRV), false)` based on that transient price. After the pool exit finishes and the LP price returns to normal, the attacker withdraws the genuine `steCRV` collateral and then liquidates the now-underwater position to recover the BPT, turning the temporary oracle distortion into permanent lender loss.

**Impact:** An attacker can use a small amount of Balancer BPT to make an account appear solvent only during the reentrant window, disable and withdraw the real collateral that was actually securing the debt, and leave the protocol with bad debt or stolen lender funds once pricing normalizes.

**Paths:**

- testExploit -> executeOperation -> Exploiter.yoink -> joinBalancerPool -> depositCollateralAndBorrow -> exitBalancerPool -> Balancer.exitPool -> receive -> SturdyOracle.getAssetPrice(cB_stETH_STABLE) -> lendingPool.setUserUseReserveAsCollateral(csteCRV,false) -> withdrawCollateralAndLiquidation -> ConvexCurveLPVault2.withdrawCollateral(steCRV,...) -> lendingPool.liquidationCall(B_STETH_STABLE,WETH,...)

*Round 1 | Agents: codex*

---
